#if DEBUG
import Foundation
import CoreGraphics
import GlassConnectionKit
import GlassRDPTransport

/// Screenshots only (`App/GlassDemoMode.swift`): a desktop window whose remote screen is a picture
/// the app drew itself. The same server-less session as `DesktopGlassWindowPreview`: the
/// operations do nothing, nothing is contacted, and the picture is the only frame it receives.
extension GlassDesktopRuntime {
    public func requestDemoDesktop(name: String, host: String, picture: CGImage) async {
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

        // Throwaway storage, so the demo never writes into the run's desktop list.
        let app = DesktopAppModel(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("glass-demo-\(UUID())"))
        await app.load()
        let connection = DesktopConnection(name: name, host: host, username: "ann")
        var operations = DesktopSessionOperations()
        operations.connect = { _, _ in }
        operations.disconnect = { _ in }
        operations.resize = { _, _, _ in }
        let model = DesktopSessionModel(connection: connection, app: app, operations: operations)
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
}
#endif
