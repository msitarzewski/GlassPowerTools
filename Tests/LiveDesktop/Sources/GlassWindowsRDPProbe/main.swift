import Foundation
import GlassRDPTransport

// A live RDP probe against a real Windows host. It reports what was negotiated and whether real
// pixels arrived, then disconnects. It never prints the password, and reads it from a file so the
// secret is not in a command line or a process list.
//
// Usage: GlassWindowsRDPProbe <host> <port> <username> <password-file>

@MainActor final class Probe {
    let session = GlassRDPSession()
    var certificate: GlassRDPCertificate?
    var capabilities: GlassRDPDisplayCapabilities?
    var firstFrame: GlassRDPFrame?
    var frameCount = 0
    var connected = false
    var failure: String?
    private var events: Task<Void, Never>?
    private var frames: Task<Void, Never>?

    init() {
        events = Task { [weak self, session] in
            for await event in session.events {
                guard !Task.isCancelled, let self else { return }
                switch event {
                case .certificate(let value): certificate = value
                case .displayCapabilities(let value): capabilities = value
                case .state(.connected): connected = true
                case .state(.failed(let message)): failure = message
                default: break
                }
            }
        }
        frames = Task { [weak self, session] in
            for await frame in session.frames {
                guard !Task.isCancelled, let self else { return }
                frameCount += 1
                if firstFrame == nil { firstFrame = frame }
            }
        }
    }

    func finish() async {
        await session.disconnect()
        events?.cancel()
        frames?.cancel()
    }
}

@main struct Main {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 5, let port = UInt16(args[2]) else {
            FileHandle.standardError.write(Data("usage: probe <host> <port> <username> <password-file> [pinned-sha256]\n".utf8))
            exit(2)
        }
        // Windows issues a self-signed RDP certificate, so a first connection is correctly refused.
        // Pinning the leaf is the real user flow: the app shows the fingerprint and the user accepts.
        let pin: String? = args.count >= 6 ? args[5] : nil
        let host = args[1], username = args[3]
        guard let password = try? String(contentsOfFile: args[4], encoding: .utf8) else {
            FileHandle.standardError.write(Data("could not read the password file\n".utf8))
            exit(2)
        }

        let probe = await Probe()
        let started = Date()
        do {
            // requiresNLA: the whole point of a Windows probe is the NLA path nothing has exercised.
            try await probe.session.connect(
                GlassRDPConfiguration(host: host, port: port, username: username,
                                      password: password.trimmingCharacters(in: .whitespacesAndNewlines),
                                      width: 1280, height: 800, requiresNLA: true,
                                      approvedCertificateSHA256: pin)
            )
        } catch {
            print("connect threw: \(error)")
            await probe.finish()
            exit(1)
        }

        // Wait up to 45s for a frame, reporting whatever we reached.
        while Date().timeIntervalSince(started) < 45 {
            if await probe.firstFrame != nil { break }
            if let failure = await probe.failure {
                print("FAILED after \(String(format: "%.1f", Date().timeIntervalSince(started)))s: \(failure)")
                if let cert = await probe.certificate {
                    print("  certificate: systemTrusted=\(cert.systemTrusted) sha256=\(cert.sha256 ?? "nil")")
                }
                await probe.finish()
                exit(1)
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        let elapsed = Date().timeIntervalSince(started)
        if let cert = await probe.certificate {
            print("certificate   : systemTrusted=\(cert.systemTrusted) accepted=\(cert.isAccepted) sha256=\(cert.sha256 ?? "nil")")
        } else { print("certificate   : none reported") }
        print("connected     : \(await probe.connected)")
        if let caps = await probe.capabilities {
            print("displayCaps   : maximumMonitors=\(caps.maximumMonitors) maximumArea=\(caps.maximumArea)")
        } else { print("displayCaps   : none reported") }
        if let frame = await probe.firstFrame {
            let nonZero = frame.pixels.contains { $0 != 0 }
            print("first frame   : \(frame.width)x\(frame.height) bytesPerRow=\(frame.bytesPerRow) after \(String(format: "%.2f", elapsed))s")
            print("pixels        : \(frame.pixels.count) bytes, nonZero=\(nonZero), hardwareAccel=\(String(describing: frame.usesHardwareAcceleration))")
            print("frames seen   : \(await probe.frameCount)")
            await probe.finish()
            print("RESULT: PASS")
            exit(0)
        }
        print("RESULT: FAIL — no frame within 45s")
        await probe.finish()
        exit(1)
    }
}
