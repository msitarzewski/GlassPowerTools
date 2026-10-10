#if DEBUG
import Foundation
import CoreGraphics
import GlassConnectionKit
import GlassLayers
import GlassRDPTransport

/// Screenshots only (`App/GlassDemoMode.swift`): a desktop window whose remote screen is a picture
/// the app drew itself. The same server-less session as `DesktopGlassWindowPreview`: the
/// operations do nothing, nothing is contacted, and the picture is the only frame it receives.
extension GlassDesktopRuntime {
    /// With `windowSettings`, the window keeps settings of its own (W25); with `opensSettings`,
    /// Desktop Settings ▸ This Window opens over it.
    public func requestDemoDesktop(name: String, host: String, picture: CGImage,
                                   windowSettings: GlassWindowOverrides = GlassWindowOverrides(),
                                   opensSettings: Bool = false) async {
        let width = picture.width, height = picture.height
        // BGRA in memory, which is what the renderer uploads (`DesktopMetalRenderer`).
        var pixels = Data(count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return }

        // Throwaway storage, so the demo never writes into the run's desktop list; its window's
        // settings are kept in memory only (the store's default).
        let app = DesktopAppModel(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("glass-demo-\(UUID())"))
        await app.load()
        let connection = DesktopConnection(name: name, host: host, username: "ann")
        var operations = DesktopSessionOperations()
        operations.connect = { _, _ in }
        operations.disconnect = { _ in }
        operations.resize = { _, _, _ in }
        let model = DesktopSessionModel(connection: connection, app: app, operations: operations)
        model.windowSettings = windowSettings
        model.demoOpensSettings = opensSettings
        do {
            try await model.connect(username: "ann", domain: nil, password: "")
            await model.receive(.state(.connected), attempt: model.attemptID, connection: connection)
            let frame = try GlassRDPFrame(width: width, height: height, bytesPerRow: width * 4,
                                          pixels: pixels, sequence: 1)
            model.receive(frame, attempt: model.attemptID)
        } catch { return }
        demoSessions[connection.id] = model
        enqueue(.show(connectionID: connection.id))
    }

    /// Screenshots only (`--demo-glass`, W28): a desktop window at a given glass — its Background
    /// Frost — and, when given, a remote screen faded to `opacity`.
    public static func demoWindowSettings(frost: Double, opacity: Double?) -> GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.frost] = frost
        if let opacity { window[DesktopWindowSettings.opacity] = opacity }
        return window
    }

    /// Screenshots only (W30): a host with two displays — `mainDisplay` and a second, smaller one
    /// drawn here, beside it and lower, as a Mac sends them: one framebuffer covering both, with the
    /// uncovered corner black — and its layout, so the desktop's window shows the main display and
    /// a window opens for the other where windows can open. The link readout is a fixed picture of
    /// a slow link, labelled as nothing else: no host, no network.
    public func requestDemoDisplays(name: String, host: String, mainDisplay: CGImage, opensSettings: Bool = false) async {
        let second = CGSize(width: 1280, height: 800), offset = 140
        let width = mainDisplay.width + Int(second.width), height = max(mainDisplay.height, offset + Int(second.height))
        var pixels = Data(count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Bitmap rows run top-down; Core Graphics' y runs up.
            context.draw(mainDisplay, in: CGRect(x: 0, y: height - mainDisplay.height,
                                                 width: mainDisplay.width, height: mainDisplay.height))
            Self.drawDemoSecondDisplay(in: context, rect: CGRect(x: CGFloat(mainDisplay.width),
                                                                 y: CGFloat(height - offset) - second.height,
                                                                 width: second.width, height: second.height))
            return true
        }
        guard drawn else { return }
        let app = DesktopAppModel(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("glass-demo-\(UUID())"))
        await app.load()
        let connection = DesktopConnection(name: name, host: host, port: 5900, username: "ann", protocol: .vnc)
        var operations = DesktopSessionOperations()
        operations.connect = { _, _ in }
        operations.disconnect = { _ in }
        operations.resize = { _, _, _ in }
        let model = DesktopSessionModel(connection: connection, app: app, operations: operations)
        model.demoOpensSettings = opensSettings
        model.demoOpensConnection = opensSettings
        do {
            try await model.connect(username: "ann", domain: nil, password: "demo")
            await model.receive(.state(.connected), attempt: model.attemptID, connection: connection)
            let frame = try GlassRDPFrame(width: width, height: height, bytesPerRow: width * 4, pixels: pixels, sequence: 1)
            model.receive(frame, attempt: model.attemptID)
            await model.receive(.screens([
                GlassRemoteScreen(id: 1, x: 0, y: 0, width: mainDisplay.width, height: mainDisplay.height, isPrimary: true),
                GlassRemoteScreen(id: 2, x: mainDisplay.width, y: offset, width: Int(second.width),
                                  height: Int(second.height), isPrimary: false),
            ]), attempt: model.attemptID, connection: connection)
            await model.receive(.linkStatistics(GlassDesktopLinkStatistics(
                bytesPerSecond: 196_000, updatesPerSecond: 11, quality: .automatic, level: .dataSaver, colourDepth: 16,
                encoding: "ZRLE", measuredKilobitsPerSecond: 2_400, regionLimited: false, paused: false)),
                                attempt: model.attemptID, connection: connection)
        } catch { return }
        demoSessions[connection.id] = model
        enqueue(.show(connectionID: connection.id))
    }

    /// The second display: a plain desktop with a notes window. Every pixel is drawn here.
    private static func drawDemoSecondDisplay(in context: CGContext, rect: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        let colours = [CGColor(red: 0.16, green: 0.30, blue: 0.36, alpha: 1), CGColor(red: 0.36, green: 0.52, blue: 0.48, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
                                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        }
        // A window: title bar and lines of text as bars.
        let window = CGRect(x: rect.minX + 120, y: rect.minY + 120, width: rect.width - 240, height: rect.height - 220)
        context.setFillColor(CGColor(gray: 0.97, alpha: 1))
        context.addPath(CGPath(roundedRect: window, cornerWidth: 14, cornerHeight: 14, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: 0.86, alpha: 1))
        context.fill(CGRect(x: window.minX, y: window.maxY - 52, width: window.width, height: 38))
        for line in 0..<12 {
            let lengths: [CGFloat] = [0.82, 0.64, 0.9, 0.48, 0.74, 0.88, 0.56, 0.7, 0.93, 0.38, 0.66, 0.8]
            context.setFillColor(line == 0 ? CGColor(red: 0.2, green: 0.4, blue: 0.85, alpha: 1) : CGColor(gray: 0.55, alpha: 1))
            context.fill(CGRect(x: window.minX + 40, y: window.maxY - 110 - CGFloat(line) * 38,
                                width: (window.width - 80) * lengths[line], height: line == 0 ? 18 : 12))
        }
    }

    /// Screenshots only: a desktop window with settings of its own (W25).
    public static var demoWindowSettings: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.opacity] = 0.85
        window[DesktopWindowSettings.frost] = 0.6
        window[DesktopWindowSettings.detail] = .oneAndAHalf
        return window
    }
}
#endif
