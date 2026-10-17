//
//  ModelFile.swift
//  Glass Power Tools — GlassEditorCore
//
//  3D model files and links (D78): which links are models, and a model under a name RealityKit
//  opens it by. RealityKit's `Entity(contentsOf:)` picks its reader from the file's extension, and
//  here a file's bytes decide what it is (`GlassEditorFileKind`) — a USDZ saved as `download` is a
//  model all the same, and is given the extension its bytes say.
//

import Foundation

public enum GlassModelFile {
    /// The extensions Apple's frameworks open a model by.
    public static let extensions: Set<String> = ["usdz", "usd", "usda", "usdc", "reality"]

    /// A web address whose file is a model: http or https, its path ending in a model's
    /// extension. The query and fragment don't count (`…/imac.usdz?v=2` is a model).
    public static func isModelLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return extensions.contains(url.pathExtension.lowercased())
    }

    /// The extension a model's opening bytes call for.
    static func `extension`(forHead head: Data) -> String {
        if head.starts(with: Data("PXR-USDC".utf8)) { return "usdc" }
        if head.starts(with: Data("#usda".utf8)) { return "usda" }
        return "usdz"
    }

    /// `url` as a file RealityKit opens: itself when its name already says what it is, else a link
    /// (or copy) under the name its bytes call for, in `directory`.
    public static func loadableURL(for url: URL,
                                   in directory: URL = FileManager.default.temporaryDirectory
                                       .appendingPathComponent("GlassModels", isDirectory: true)) throws -> URL {
        if extensions.contains(url.pathExtension.lowercased()) { return url }
        let handle = try FileHandle(forReadingFrom: url)
        let head = try handle.read(upToCount: 64) ?? Data()
        try handle.close()
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
        let target = folder.appendingPathComponent((base.isEmpty ? "model" : base) + "." + `extension`(forHead: head))
        do {
            try FileManager.default.linkItem(at: url, to: target)
        } catch {
            try FileManager.default.copyItem(at: url, to: target)
        }
        return target
    }

    /// Whether Apple's Quick Look opens the model — AR Quick Look on iPhone and iPad, the volume on
    /// Vision Pro: a USDZ or a Reality file. A bare USD layer it calls "not supported" (measured,
    /// visionOS 27.2 simulator), so those stay in the app's own viewer.
    public static func quickLookOpens(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "reality" { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return GlassEditorFileKind.isUSDZ((try? handle.read(upToCount: 30 + 1024)) ?? Data())
    }

    /// Whether a model file is text a person can edit: a USD layer in its text form.
    public static func isText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 5)) == Data("#usda".utf8)
    }
}
