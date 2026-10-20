//
//  TerminalBackgroundPictures.swift
//  Glass Power Tools — GlassTerminal
//
//  The pictures terminal windows show behind their text (D84). A window's settings are a few
//  short values, synced with a saved Workgroup, so a picture lives here, on this device, and the
//  window keeps only its name: a UUID and an extension, never a path. A name another device sent
//  that this one doesn't have shows no picture.
//
//  Kept small: a picture is scaled to fit 2560 pixels and stored as JPEG, whatever was chosen.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import GlassLayers

nonisolated enum TerminalBackgroundPictures {
    /// Longest side kept, in pixels: a full-screen window on a large display, no more.
    static let maximumPixelSize = 2_560
    /// A file larger than this isn't read: no picture is, and one that claims to be could be anything.
    static let maximumInputBytes = 80 * 1_024 * 1_024

    enum ImportError: LocalizedError, Equatable {
        case tooLarge
        case notAPicture
        case cannotSave

        var errorDescription: String? {
            switch self {
            case .tooLarge: "That picture is too large. Choose one under 80 MB."
            case .notAPicture: "That file isn't a picture this app can show. Choose a JPEG, PNG, HEIC or similar."
            case .cannotSave: "The picture couldn't be saved. Check that this device has free space, then try again."
            }
        }
    }

    /// A name this store gives: `<UUID>.jpg`. Anything else — a path, a name from elsewhere — isn't one.
    static func isName(_ name: String) -> Bool {
        guard name.hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    /// Application Support's `GlassPowerTools/Terminal Backgrounds`, or a run's own folder while a
    /// UI test drives the app.
    static var directory: URL {
        if let run = GlassUITestRun.identifier {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("GlassPowerTools-uitests-\(run.uuidString)", isDirectory: true)
                .appendingPathComponent("Terminal Backgrounds", isDirectory: true)
        }
        return URL.applicationSupportDirectory
            .appendingPathComponent("GlassPowerTools", isDirectory: true)
            .appendingPathComponent("Terminal Backgrounds", isDirectory: true)
    }

    static func url(for name: String, in directory: URL = directory) -> URL? {
        guard isName(name) else { return nil }
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    /// Keeps `data` as a picture and returns its name: scaled to fit, its orientation applied, as JPEG.
    static func importPicture(_ data: Data, into directory: URL = directory) throws -> String {
        guard data.count <= maximumInputBytes else { throw ImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { throw ImportError.notAPicture }
        let name = UUID().uuidString + ".jpg"
        guard let url = url(for: name, in: directory) else { throw ImportError.cannotSave }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ImportError.cannotSave
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ImportError.cannotSave }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.cannotSave }
        return name
    }

    /// The picture named `name`, decoded, or nil when this device doesn't have it.
    static func image(named name: String, in directory: URL = directory) -> CGImage? {
        guard let url = url(for: name, in: directory),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// How bright the picture's brighter parts are (relative luminance, 0…1): the 90th percentile
    /// over a small copy, so a bright patch behind some of the text counts, not only the average.
    static func brightness(of image: CGImage) -> Double {
        let width = 32, height = 20
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 1 }
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            values.append(TerminalReadability.luminance(red: Double(pixels[index]) / 255,
                                                        green: Double(pixels[index + 1]) / 255,
                                                        blue: Double(pixels[index + 2]) / 255))
        }
        values.sort()
        return values[min(values.count - 1, Int(Double(values.count) * 0.9))]
    }
}
