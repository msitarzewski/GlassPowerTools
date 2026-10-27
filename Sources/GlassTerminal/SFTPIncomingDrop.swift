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
//  **What is genuinely AppKit here** is the fast path: `NSFilePromiseReceiver`, and reading the
//  drag pasteboard synchronously before another drag can replace it. Both are macOS-only APIs and
//  stay behind a check that names them. `NSItemProvider` is the path every other platform uses,
//  and AppKit already falls back to it.
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
        #if os(macOS)
        case promise(NSFilePromiseReceiver)
        #endif
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

    #if os(macOS)
    /// Snapshot the drag pasteboard synchronously, before another drag can replace it.
    /// AppKit chooses one representation per item, preferring its file promise.
    init?(providers: [NSItemProvider], pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        guard !PromiseRetention.shared.hasActivePromises else { return nil }
        let native = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self, NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) ?? []
        let sources: [Source] = native.compactMap {
            if let promise = $0 as? NSFilePromiseReceiver { return .promise(promise) }
            if let url = $0 as? URL, url.isFileURL { return .file(url) }
            return nil
        }
        self.sources = sources.isEmpty ? providers.map(Source.provider) : sources
        if self.sources.isEmpty { return nil }
    }
    #else
    /// Everywhere else there is no drag pasteboard to race: the system hands over item providers
    /// and nothing else, which is the path AppKit falls back to anyway.
    init?(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return nil }
        sources = providers.map(Source.provider)
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

    /// Files that already exist come back as they are; promised files and bare content are
    /// written into `staging` — by default, a temporary one that goes when it is released.
    #if os(macOS)
    /// What a file promise calls with each file. AppKit calls it on the receive queue, never the
    /// main thread: written inline in this main-actor class it was main-actor code, and Swift
    /// stopped the app the moment AppKit called it (2026-10-09, a screenshot's thumbnail dropped
    /// on a terminal). It touches only what is safe from any thread, and keeps the staging alive
    /// for late callbacks even if the drop's task was cancelled.
    nonisolated static func promiseReader(staging: SFTPDropStaging,
                                          continuation: AsyncThrowingStream<URL, Error>.Continuation)
        -> @Sendable (URL, (any Error)?) -> Void {
        { url, error in
            withExtendedLifetime(staging) {
                if let error { continuation.finish(throwing: error) } else { continuation.yield(url) }
            }
        }
    }
    #endif

    func materialize(into given: SFTPDropStaging? = nil) async throws -> (urls: [URL], staging: SFTPDropStaging) {
        let staging = try given ?? SFTPDropStaging()
        var urls: [URL] = []
        for source in sources {
            try Task.checkCancellation()
            switch source {
            case .file(let url):
                urls.append(url)
            #if os(macOS)
            case .promise(let receiver):
                let expected = max(receiver.fileNames.count, 1)
                let queue = OperationQueue()
                queue.name = "sh.glas.receive-file-promise"
                queue.maxConcurrentOperationCount = 1
                let stream = AsyncThrowingStream<URL, Error> { continuation in
                    receiver.receivePromisedFiles(atDestination: staging.directory, options: [:],
                                                  operationQueue: queue,
                                                  reader: Self.promiseReader(staging: staging, continuation: continuation))
                }
                var received = 0
                for try await url in stream {
                    try Task.checkCancellation()
                    guard staging.owns(url) else {
                        throw CocoaError(.fileReadNoPermission)
                    }
                    urls.append(url)
                    received += 1
                    if received == expected { break }
                }
            #endif
            case .provider(let provider), .pasted(let provider):
                if case .provider = source, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let stream = AsyncThrowingStream<URL, Error> { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                            do {
                                if let error { throw error }
                                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                                      url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
                                let accessed = url.startAccessingSecurityScopedResource()
                                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                                continuation.yield(try staging.retainFile(url, suggestedName: nil))
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
