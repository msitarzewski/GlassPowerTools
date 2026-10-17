//
//  TerminalModelLinks.swift
//  Glass Power Tools — GlassTerminal
//
//  A terminal's link to a 3D model, opened in 3D here (D78 — the owner, 2026-10-16, asked: "Open it
//  in 3D here", for links like Apple's `…/imac-with-accessories-blue.usdz`). After the confirmation
//  every terminal link gets, the file is downloaded, checked to be a model by its bytes, and shown:
//  the Mac in the editor's viewer (RealityKit), iPhone and iPad in Apple's AR Quick Look, Vision Pro
//  in Apple's Quick Look volume.
//
//  The link comes from what a terminal printed, so it is the confirmation's to approve, http or
//  https only (`SwiftTermExternalLinkPolicy`), at most `maximumBytes`, and kept only if its bytes
//  are a model's; the file goes in the app's caches, in a folder of its own, cleared after a week
//  (`TerminalDroppedPaths.inbox`).
//

import Foundation
import Observation
import OSLog
import SwiftUI
import GlassEditorCore
#if os(visionOS) || os(iOS)
import QuickLook
#endif

nonisolated enum TerminalModelDownload {
    static let maximumBytes: Int64 = 512 * 1024 * 1024
    static let folderName = "Models"

    enum Failure: LocalizedError, Equatable {
        case notAModel(name: String)
        case tooLarge(bytes: Int64, limit: Int64)
        case server(status: Int)

        var errorDescription: String? {
            switch self {
            case .notAModel(let name):
                "\(name) isn't a 3D model this app can show. The link may lead to a web page or another kind of file; open it in a browser instead."
            case .tooLarge(let bytes, let limit):
                "The model is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), more than the \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)) this app downloads. Open the link in a browser instead."
            case .server(let status):
                "The server answered \(status) (\(HTTPURLResponse.localizedString(forStatusCode: status))) instead of sending the model. Try the link again later, or in a browser."
            }
        }
    }

    /// The file's name, from the link: its last path component, or "model.usdz".
    static func fileName(for url: URL) -> String {
        let name = url.lastPathComponent.replacingOccurrences(of: "/", with: "")
        return name.isEmpty || name == "." || name == ".." ? "model.usdz" : name
    }

    /// Downloads `url` into a folder of its own in `inbox`, and returns the file if it is a model.
    static func download(_ url: URL, session: URLSession, inbox: URL,
                         limit: Int64 = maximumBytes) async throws -> URL {
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.server(status: http.statusCode)
        }
        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size <= limit else { throw Failure.tooLarge(bytes: size, limit: limit) }
        let name = fileName(for: url)
        let handle = try FileHandle(forReadingFrom: temporary)
        let head = try handle.read(upToCount: GlassEditorFileKind.sniffLength) ?? Data()
        try handle.close()
        guard GlassEditorFileKind.classify(name: name, prefix: head) == .model3D else {
            throw Failure.notAModel(name: name)
        }
        let folder = inbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: temporary, to: file)
        return file
    }
}

/// One terminal view's model links: downloading, a failure to say, and — iPhone, iPad — the model
/// for Apple's AR Quick Look.
@MainActor
@Observable
final class TerminalModelLinkOpener {
    private(set) var downloading = false
    var failure: String?
    var preview: URL?
    private let session: URLSession
    private static let logger = Logger(subsystem: "sh.glas", category: "terminal-model-link")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func open(_ url: URL) {
        guard !downloading else { return }
        downloading = true
        Task { @MainActor in
            defer { downloading = false }
            do {
                let inbox = try TerminalDroppedPaths.inbox(named: TerminalModelDownload.folderName)
                let file = try await TerminalModelDownload.download(url, session: session, inbox: inbox)
                show(file)
            } catch {
                Self.logger.error("A model link couldn't be opened: \(error.localizedDescription, privacy: .public)")
                failure = error.localizedDescription
            }
        }
    }

    /// Apple's Quick Look where it opens the model (a USDZ or Reality file, off the Mac); the editor's
    /// viewer otherwise.
    private func show(_ file: URL) {
        #if os(visionOS)
        if GlassModelFile.quickLookOpens(file) {
            _ = PreviewApplication.open(urls: [file])
            return
        }
        #elseif os(iOS)
        if GlassModelFile.quickLookOpens(file) {
            preview = file
            return
        }
        #endif
        GlassTerminalRuntime.current?.openLocalInEditor?([file])
    }
}

/// What a terminal view shows of its model links: a download under way, a failure in words, and
/// (iPhone, iPad) Apple's AR Quick Look.
struct TerminalModelLinkPresentation: ViewModifier {
    @Bindable var opener: TerminalModelLinkOpener

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if opener.downloading {
                    Label("Downloading 3D model…", systemImage: "arrow.down.circle")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 12)
                        .accessibilityIdentifier("terminal-model-downloading")
                }
            }
            .alert("Couldn't Open the Model", isPresented: Binding(
                get: { opener.failure != nil },
                set: { if !$0 { opener.failure = nil } }
            )) {
                Button("OK", role: .cancel) { opener.failure = nil }
            } message: {
                Text(opener.failure ?? "")
            }
            #if os(iOS)
            .quickLookPreview($opener.preview)
            #endif
    }
}
