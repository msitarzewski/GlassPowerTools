#if DEBUG && os(visionOS) && targetEnvironment(simulator)
import SwiftUI
import UIKit
import GlassRDPTransport

/// Explicit simulator-only native-window fixture; never contacts a host.
public struct DesktopGlassWindowPreview: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var session: DesktopSessionModel?
    @State private var failure: String?
    public init() {}
    public var body: some View {
        Group {
            if let session { DesktopSessionView(previewSession: session) }
            else if let failure { Text(failure) }
            else { ProgressView("Preparing glass fixture…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { dismissWindow(id: "library") }
        .task {
            guard session == nil else { return }
            do {
                let environment = ProcessInfo.processInfo.environment
                if environment["GLASSDT_RESET_GLASS_PREVIEW"] == "1" {
                    for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("display.glass.") {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("glass-preview-\(UUID())")
                // No shared directory any more: the shell owns the catalog, so a preview needs
                // only its own throwaway storage.
                let app = DesktopAppModel(storageDirectory: directory)
                await app.load()
                let connection = DesktopConnection(name: "Glass Window Preview", host: "preview.invalid", username: "preview")
                var operations = DesktopSessionOperations()
                operations.connect = { _, _ in }
                operations.disconnect = { _ in }
                operations.resize = { _, _, _ in }
                let model = DesktopSessionModel(connection: connection, app: app, operations: operations)
                try await model.connect(username: "preview", domain: nil, password: "")
                await model.receive(.state(.connected), attempt: model.attemptID, connection: connection)
                let width: Int, height: Int
                switch environment["GLASSDT_GLASS_PREVIEW_PROFILE"] {
                case "portrait": width = 720; height = 1280
                case "wide": width = 1920; height = 720
                default: width = 1280; height = 720
                }
                // Solid magenta desktop plus an opaque mock application. Black,
                // white and cyan foreground pixels must survive magenta keying.
                var pixels = Data(count: width * height * 4)
                pixels.withUnsafeMutableBytes { raw in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    for y in 0..<height { for x in 0..<width {
                        let i = (y * width + x) * 4
                        let inside = x > width / 5 && x < width * 4 / 5 && y > height / 5 && y < height * 4 / 5
                        let title = inside && y < height / 3
                        let line = inside && y > height / 3 && y % 60 < 10 && x < width * 3 / 5
                        let color: (UInt8, UInt8, UInt8) = !inside ? (255, 0, 255) : title ? (240, 240, 240) : line ? (0, 0, 0) : (230, 190, 30)
                        bytes[i] = color.0; bytes[i + 1] = color.1; bytes[i + 2] = color.2; bytes[i + 3] = 255
                    } }
                }
                let frame = try GlassRDPFrame(width: width, height: height, bytesPerRow: width * 4, pixels: pixels, sequence: 1)
                model.receive(frame, attempt: model.attemptID)
                session = model
            } catch { failure = error.localizedDescription }
        }
    }
}
#endif
