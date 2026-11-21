//
//  SFTPIncomingDrop.swift
//  Glass Power Tools — GlassTerminal
//
//  A file dragged **into** the Files browser from another application.
//
//  This lived in `macOS/SFTPFilePromiseDragSource.swift`, and was therefore macOS-only — not
//  because receiving a drop is a Mac idea, but because the file it happened to be written in is
//  fenced with `#if os(macOS)`. iPadOS has had cross-application drag and drop for years and has
//  real window management now, and the iPhone Duo's inner display brings the same gesture to a
//  phone in October. The platform check was standing in for a capability question and answering
//  it wrongly (2026-09-20).
//
//  A drop arrives through `NSItemProvider` on every platform, a file promise included. **What is
//  genuinely AppKit here** is the Files browser's paste of files copied in Finder, read off the
//  general pasteboard. Until 2026-11-20 a Mac drop read the drag pasteboard and called its file
//  promises in with `NSFilePromiseReceiver`; why it doesn't is on `init(providers:)`.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Owns only a uniquely-created drop directory, including while a source is
/// still exporting after cancellation. Never deletes a source application's file.
final class SFTPDropStaging: @unchecked Sendable {
    let directory: URL
    /// A terminal's drop keeps what it received: the paths are typed into the shell, and a program
    /// reads them after the drop is over. An upload's staging is gone once the upload is.
    private let keepsFiles: Bool

    convenience init() throws {
        try self.init(in: FileManager.default.temporaryDirectory, prefix: "glas-sh-drop-", keepsFiles: false)
    }

    /// A directory of its own inside `parent`, whose files outlive the drop.
    convenience init(keepingFilesIn parent: URL) throws {
        try self.init(in: parent, prefix: "", keepsFiles: true)
    }

    private init(in parent: URL, prefix: String, keepsFiles: Bool) throws {
        directory = parent.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        self.keepsFiles = keepsFiles
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: keepsFiles,
                                               attributes: [.posixPermissions: 0o700])
    }

    deinit { if !keepsFiles { try? FileManager.default.removeItem(at: directory) } }

    nonisolated func owns(_ url: URL) -> Bool {
        url.isFileURL && url.resolvingSymlinksInPath().path.hasPrefix(
            directory.resolvingSymlinksInPath().path + "/"
        )
    }

    nonisolated static func filename(_ suggestion: String?, fallback: String) -> String {
        guard let suggestion, !suggestion.isEmpty, suggestion != ".", suggestion != "..",
              !suggestion.contains("/"), !suggestion.contains(":"),
              !suggestion.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return fallback }
        return suggestion
    }

    nonisolated func retainFile(_ source: URL, suggestedName: String?) throws -> URL {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard source.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var name = Self.filename(suggestedName, fallback: source.lastPathComponent)
        if (name as NSString).pathExtension.isEmpty, !source.pathExtension.isEmpty {
            name += "." + source.pathExtension
        }
        let target = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}

@MainActor
final class SFTPIncomingDrop {
    /// What this target accepts. The promise types are AppKit's own; the rest are what any
    /// application on any of these platforms offers when it hands over a file.
    static let acceptedTypes: [String] = {
        let common = [UTType.fileURL.identifier, UTType.image.identifier, UTType.movie.identifier,
                      UTType.pdf.identifier, UTType.plainText.identifier]
        #if os(macOS)
        return NSFilePromiseReceiver.readableDraggedTypes + common
        #else
        return common
        #endif
    }()

    private enum Source {
        case file(URL)
        case provider(NSItemProvider)
        /// An item pasted: read for its content, never a file URL the clipboard names, which this
        /// app may not be allowed to open.
        case pasted(NSItemProvider)
    }
    private let sources: [Source]

    /// Items pasted on a terminal that are pictures or files (`isPastedFile`); nil when none are,
    /// and the paste is text.
    init?(pasted providers: [NSItemProvider]) {
        let files = providers.filter { Self.isPastedFile($0.registeredTypeIdentifiers) }
        guard !files.isEmpty else { return nil }
        sources = files.map(Source.pasted)
    }

    /// A drop, read through the item providers SwiftUI's `onDrop` hands over for it and nothing else, on every
    /// platform. A Mac file that exists (Finder's) comes back as itself (`materialize`).
    ///
    /// **The Mac's drag pasteboard is not read, and no file promise is called in here** (2026-11-20). This read
    /// `NSPasteboard(name: .drag)` first, and two things were wrong with that:
    /// - Not every drag is on it. A stack in the Dock drags on its own, and the drag pasteboard still held the drag
    ///   before: an SVG from the Downloads stack typed the path of a different file, dragged a minute earlier.
    /// - It called the file promises it found in, from the drop's task after the drop. SwiftUI's `onDrop` has already
    ///   called each promise in, into a folder of its own, and its providers carry the files. On macOS 26 a modern
    ///   promise called in again handed back SwiftUI's file, refused as not this drop's, and a legacy one (the Dock's)
    ///   waited a minute and failed. macOS 27 raises `NSInternalInconsistencyException` ("receivePromisedFilesAt
    ///   Destination:… can only be called during -prepareForDragOperation:, -performDragOperation:, and
    ///   -concludeDragOperation:") through that task, and on macOS 27.2.1 the app quit 90 ms later, in Swift's
    ///   main-thread check (an SVG dragged from the Dock's Downloads stack onto a terminal).
    init?(providers: [NSItemProvider]) {
        #if os(macOS)
        // This app's own drag from the Files browser, offered back to it.
        guard !PromiseRetention.shared.hasActivePromises else { return nil }
        #endif
        guard !providers.isEmpty else { return nil }
        sources = providers.map(Source.provider)
    }

    #if os(macOS)
    /// Files copied in Finder (`pasteFilesFromFinder`), by their own paths; nil when the pasteboard holds none. A file
    /// promise copied is not taken: one can't be called in outside a drag (macOS 27 raises).
    init?(filesOn pasteboard: NSPasteboard) {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
                     as? [URL] ?? []).filter(\.isFileURL)
        guard !files.isEmpty else { return nil }
        sources = files.map(Source.file)
    }
    #endif

    /// A representation that arrives as one regular file: any content or data — a zip from Files
    /// is data, not "content" — but not a link, and not a package or folder (a Live Photo's
    /// bundle, say), which `retainFile` would refuse after the copy (W14, 2026-10-09).
    nonisolated static func isReadableAsOneFile(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return (type.conforms(to: .content) || type.conforms(to: .data))
            && !type.conforms(to: .url)
            && !type.conforms(to: .package)
            && !type.conforms(to: .directory)
    }

    /// Whether an item pasted is a file to send rather than text to type: a picture, whatever else
    /// it carries (a photo, a screenshot); else anything held as one file with no text beside it (a
    /// PDF). Text, a web link, and types the system doesn't know are typed as text, as before.
    nonisolated static func isPastedFile(_ identifiers: [String]) -> Bool {
        let types = identifiers.compactMap(UTType.init).filter(\.isDeclared)
        if types.contains(where: { $0.conforms(to: .image) }) { return true }
        if types.contains(where: { $0.conforms(to: .text) || $0.conforms(to: .url) && !$0.conforms(to: .fileURL) }) {
            return false
        }
        return types.contains { isReadableAsOneFile($0) }
    }

    /// The representation a file is read as: a picture first, where an item offers one beside
    /// other things, else the first that arrives as one file.
    nonisolated static func fileType(in identifiers: [String]) -> String? {
        let readable = identifiers.filter { isReadableAsOneFile(UTType($0)) }
        return readable.first { UTType($0)?.conforms(to: .image) == true } ?? readable.first
    }

    /// A file that exists only for a drop, which won't be kept: SwiftUI's copy of a promised file, under the caches
    /// folder (`com.apple.SwiftUI.filePromises-…`), or one in a temporary folder.
    nonisolated static func isHeldOnlyForTheDrop(
        _ url: URL,
        holding: [URL] = [FileManager.default.temporaryDirectory]
            + FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    ) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return holding.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    /// Files that already exist come back as they are; promised files and bare content, from their
    /// providers, are written into `staging` — by default, a temporary one that goes when it is released.
    func materialize(into given: SFTPDropStaging? = nil) async throws -> (urls: [URL], staging: SFTPDropStaging) {
        let staging = try given ?? SFTPDropStaging()
        var urls: [URL] = []
        for source in sources {
            try Task.checkCancellation()
            switch source {
            case .file(let url):
                urls.append(url)
            case .provider(let provider), .pasted(let provider):
                if case .provider = source, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let stream = AsyncThrowingStream<URL, Error> { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                            do {
                                if let error { throw error }
                                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                                      url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
                                #if os(macOS)
                                // As it is, a folder too: the app isn't sandboxed, and a terminal types the file's
                                // own path, as Terminal does.
                                continuation.yield(url)
                                #else
                                let accessed = url.startAccessingSecurityScopedResource()
                                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                                continuation.yield(try staging.retainFile(url, suggestedName: nil))
                                #endif
                                continuation.finish()
                            } catch { continuation.finish(throwing: error) }
                        }
                    }
                    for try await url in stream { urls.append(url) }
                    continue
                }
                guard let identifier = Self.fileType(in: provider.registeredTypeIdentifiers) else {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
                // A picture pasted comes with no name; on the host it is "Pasted", by its type.
                let pasted = if case .pasted = source { true } else { false }
                let name = provider.suggestedName ?? (pasted
                    ? UTType(identifier)?.preferredFilenameExtension.map { "Pasted." + $0 } ?? "Pasted" : nil)
                #if os(macOS)
                if !pasted {
                    // A file of a type the drop names (a picture, a PDF, text) dragged from Finder or a Dock stack comes
                    // in place, and is typed by its own path, as Terminal does. So does a promised file, in the folder
                    // SwiftUI received it into (~/Library/Caches/com.apple.SwiftUI.filePromises-…), which isn't kept:
                    // that, and anything in a temporary folder, is copied into the drop's own, as bare content is.
                    let stream = AsyncThrowingStream<URL, Error> { continuation in
                        provider.loadInPlaceFileRepresentation(forTypeIdentifier: identifier) { url, inPlace, error in
                            do {
                                if let error { throw error }
                                guard let url else { throw CocoaError(.fileReadUnknown) }
                                continuation.yield(inPlace && !Self.isHeldOnlyForTheDrop(url)
                                                   ? url : try staging.retainFile(url, suggestedName: name))
                                continuation.finish()
                            } catch { continuation.finish(throwing: error) }
                        }
                    }
                    for try await url in stream { urls.append(url) }
                    continue
                }
                #endif
                let stream = AsyncThrowingStream<URL, Error> { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                        do {
                            if let error { throw error }
                            guard let url else { throw CocoaError(.fileReadUnknown) }
                            // NSItemProvider deletes its temporary file after this callback.
                            let retained = try staging.retainFile(url, suggestedName: name)
                            continuation.yield(retained)
                            continuation.finish()
                        } catch { continuation.finish(throwing: error) }
                    }
                }
                for try await url in stream { urls.append(url) }
            }
        }
        try Task.checkCancellation()
        return (urls, staging)
    }
}
