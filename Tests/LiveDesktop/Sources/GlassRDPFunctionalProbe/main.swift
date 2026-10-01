import CoreGraphics
import Foundation
import GlassRDPTransport
import ImageIO
import UniformTypeIdentifiers
import Darwin

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case let .failed(message): message } }
}

@MainActor final class Observation {
    let session = GlassRDPSession()
    var certificate: GlassRDPCertificate?
    var capabilities: GlassRDPDisplayCapabilities?
    var frame: GlassRDPFrame?
    var frameCount = 0
    var connected = false
    var failure: String?
    var clipboard: String?
    var events: Task<Void, Never>?
    var frames: Task<Void, Never>?

    init() {
        events = Task { [weak self, session] in
            for await event in session.events {
                guard !Task.isCancelled, let self else { return }
                switch event {
                case .certificate(let value): certificate = value
                case .displayCapabilities(let value): capabilities = value
                case .clipboard(let value): clipboard = value.text
                case .state(.connected): connected = true
                case .state(.failed(let value)): failure = value
                default: break
                }
            }
        }
        frames = Task { [weak self, session] in
            for await value in session.frames {
                guard !Task.isCancelled, let self else { return }
                frame = value; frameCount += 1
            }
        }
    }

    func close() async { await session.disconnect(); events?.cancel(); frames?.cancel() }
}

@main struct GlassRDPFunctionalProbe {
    @MainActor static func main() async {
        do { try await run(); exit(0) }
        catch { log(["result": "failure", "error": String(describing: error)]); exit(1) }
    }

    @MainActor static func run() async throws {
        guard CommandLine.arguments.count == 5, let port = UInt16(CommandLine.arguments[1]) else {
            throw ProbeError.failed("usage: probe localhost-port password-file container-name artifact-directory")
        }
        let password = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let container = CommandLine.arguments[3]
        let artifactDirectory = CommandLine.arguments[4]
        var configuration = GlassRDPConfiguration(host: "127.0.0.1", port: port, username: "glassfixture",
            password: password, width: 1024, height: 768, requiresNLA: false, clipboardEnabled: true)
        let rejected = Observation()
        try await rejected.session.connect(configuration)
        try await wait(seconds: 20) { rejected.failure != nil }
        guard let certificate = rejected.certificate, let sha = certificate.sha256,
              !certificate.isAccepted, !rejected.connected, rejected.frameCount == 0 else {
            throw ProbeError.failed("untrusted certificate did not terminate before desktop/input activation")
        }
        await rejected.close()
        log(["certificate_rejection": "passed", "frames_before_authorization": 0])
        configuration.approvedCertificateSHA256 = sha

        let live = Observation()
        try await live.session.connect(configuration)
        do {
            try await wait(seconds: 45) { try check(live); return live.frame != nil && live.connected }
            try writePNG(try requireFrame(live), path: "\(artifactDirectory)/first-desktop.png")
            log(["authenticated_desktop": "passed", "width": live.frame!.width, "height": live.frame!.height,
                 "hardware_decode": live.frame!.usesHardwareAcceleration.map { $0 as Any } ?? "unknown"])
            try await Task.sleep(for: .seconds(2))
            let marker = "GLASS_INPUT_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            try await live.session.sendText("printf '%s' '\(marker)' > /tmp/glass-input-proof")
            try await live.session.keyboard(scancode: 0x1c, isDown: true)
            try await live.session.keyboard(scancode: 0x1c, isDown: false)
            try await wait(seconds: 15) {
                try check(live)
                return (try? docker(["exec", container, "cat", "/tmp/glass-input-proof"])) == marker
            }
            log(["remote_keyboard_input": "passed"])
            try writePNG(try requireFrame(live), path: "\(artifactDirectory)/input-desktop.png")

            try await wait(seconds: 15) { try check(live); return live.capabilities != nil }
            guard live.capabilities?.supports(width: 1280, height: 800) == true else {
                throw ProbeError.failed("xrdp did not negotiate the requested display capability")
            }
            do { try await live.session.resize(width: 1280, height: 800) }
            catch {
                try await Task.sleep(for: .milliseconds(100))
                try check(live)
                throw error
            }
            try await wait(seconds: 20) { try check(live); return live.frame?.width == 1280 && live.frame?.height == 800 }
            try await Task.sleep(for: .seconds(2))
            try check(live)
            try writePNG(try requireFrame(live), path: "\(artifactDirectory)/resized-desktop.png")
            log(["source_resize": "passed", "width": 1280, "height": 800])

            let display = try docker(["exec", container, "sh", "-c", "find /tmp/.X11-unix -name 'X*' -type s | head -1"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let displayNumber = display.split(separator: "X").last, Int(displayNumber) != nil else {
                throw ProbeError.failed("no isolated X11 display found")
            }
            let clipboardPrefix = ["exec", "--user", "glassfixture", "--env", "DISPLAY=:\(displayNumber)", container]
            try await live.session.sendClipboard("GLASS_CLIENT_CLIPBOARD")
            try await wait(seconds: 10) {
                (try? docker(clipboardPrefix + ["timeout", "3", "xclip", "-selection", "clipboard", "-o"])) == "GLASS_CLIENT_CLIPBOARD"
            }
            _ = try docker(clipboardPrefix + ["sh", "-c", "printf GLASS_SERVER_CLIPBOARD | xclip -selection clipboard -i >/dev/null 2>&1"])
            try await wait(seconds: 10) { try check(live); return live.clipboard == "GLASS_SERVER_CLIPBOARD" }
            log(["clipboard_bidirectional": "passed"])
            await live.close()
        } catch { await live.close(); throw error }

        let reconnect = Observation()
        try await reconnect.session.connect(configuration)
        do {
            try await wait(seconds: 30) { try check(reconnect); return reconnect.frame != nil && reconnect.connected }
            log(["reconnect": "passed", "frames": reconnect.frameCount])
            await reconnect.close()
        } catch { await reconnect.close(); throw error }
        log(["result": "passed"])
    }

    @MainActor static func wait(seconds: Double, until condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while try !condition() {
            guard Date() < deadline else { throw ProbeError.failed("timed out waiting for functional evidence") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @MainActor static func check(_ observation: Observation) throws {
        if let failure = observation.failure { throw ProbeError.failed(failure) }
    }
    @MainActor static func requireFrame(_ observation: Observation) throws -> GlassRDPFrame {
        guard let frame = observation.frame else { throw ProbeError.failed("missing desktop frame") }
        return frame
    }
    static func log(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        }
    }
    static func docker(_ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOCKER_BIN"] ?? "/opt/homebrew/bin/docker")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProbeError.failed("isolated fixture command failed") }
        return String(decoding: data, as: UTF8.self)
    }
    static func writePNG(_ frame: GlassRDPFrame, path: String) throws {
        guard let provider = CGDataProvider(data: frame.pixels as CFData),
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: frame.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ProbeError.failed("could not create desktop evidence image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ProbeError.failed("could not write desktop evidence image") }
    }
}
