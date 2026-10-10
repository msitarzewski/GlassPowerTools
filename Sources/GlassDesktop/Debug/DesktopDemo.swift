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
