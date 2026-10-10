//
//  TerminalRemoteDrop.swift
//  Glass Power Tools — GlassTerminal
//
//  Files dropped on an SSH terminal go to the host, and the host's paths are typed (W14,
//  2026-10-09: "I need to be able to drag from the photos app in VisionOS into a terminal window,
//  just like mac"). On iPhone, iPad and Vision Pro every terminal is SSH, and a path on the device
//  means nothing to a shell on another machine; a Mac's SSH pane is the same.
//
//  Each file goes up with the Files browser's own verified, no-clobber upload into a drop folder,
//  `~/.cache/glass-power-tools/dropped/<date>/`, never the shell's current folder, so nothing lands
//  in a repository by accident. Then the paths are typed at the cursor as the Mac types its own:
//  escaped, space-separated, a trailing space, never run. A file that didn't arrive types nothing.
//  A photo in HEIC goes as JPEG, which the tools that read these paths (Claude Code) can open.
//  Day folders older than a week are cleared, quietly, once per connection.
//
//  Insert Path in a terminal's Files browser types paths the same way (`insertPaths`).
//

import Foundation
import GlassSSHTransport
import GlassTerminalEmulator
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - The plan: names, folders and the text typed

nonisolated enum TerminalRemoteDropPlan {
    /// The drop folder, under the home folder on the host.
    static let folder = ".cache/glass-power-tools/dropped"
    /// Day folders older than this many days are cleared.
    static let keptDays = 7

    static func root(home: String) -> String {
        (home.hasSuffix("/") ? home : home + "/") + folder
    }

    /// One folder per day, by this device's calendar: `2026-10-09`.
    static func dayName(for date: Date, timeZone: TimeZone = .current) -> String {
        dayFormatter(timeZone).string(from: date)
    }

    /// The day a folder is named for, when it is one of ours.
    static func day(named name: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = dayFormatter(timeZone)
        guard let date = formatter.date(from: name), formatter.string(from: date) == name else { return nil }
        return date
    }

    /// The day folders whose every file is more than a week old: named for a day before the
    /// seventh day back. Anything not named as a day is not ours and stays.
    static func expiredDays(_ names: [String], now: Date, timeZone: TimeZone = .current) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: calendar.startOfDay(for: now)) else {
            return []
        }
        return names.filter { name in day(named: name, timeZone: timeZone).map { $0 < cutoff } ?? false }
    }

    private static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// The name a dropped file goes by on the host: its own, as one safe path component.
    static func remoteName(for localName: String) -> String {
        let trimmed = localName.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var scalars = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                scalars.append("_")
            default:
                scalars.append(scalar == "/" || scalar == "\\" ? "_" : scalar)
            }
        }
        let name = String(scalars)
        return SFTPBrowserView.isSafeBasename(name) ? name : "dropped-file"
    }

    /// How names are compared for uniqueness: as the browser compares them, ignoring case and
    /// Unicode form, so a name is unique on a host whose file system ignores case too.
    static func collisionKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// `name`, or `name-2`, `name-3`… before the extension, unique among `taken` (collision keys),
    /// which it joins. A hyphen, not the browser's "name (2)": the path is typed into a shell.
    static func uniqueName(_ name: String, taken: inout Set<String>) -> String {
        if taken.insert(collisionKey(name)).inserted { return name }
        let pathExtension = (name as NSString).pathExtension
        let stem = pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidate = pathExtension.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(pathExtension)"
            if taken.insert(collisionKey(candidate)).inserted { return candidate }
            index += 1
        }
    }

    /// What a finished drop types: the paths of the files that arrived, in the order dropped.
    static func typedText(for outcomes: [TerminalRemoteDropOutcome]) -> String? {
        TerminalDroppedPaths.text(forPaths: outcomes.compactMap(\.remotePath))
    }

    /// What the terminal says about the files that didn't arrive; nil when every one did.
    static func failureMessage(for outcomes: [TerminalRemoteDropOutcome]) -> String? {
        let failed = outcomes.filter { $0.failure != nil }
        guard let first = failed.first, let reason = first.failure?.reason else { return nil }
        if failed.count == 1 { return "Couldn't upload \(first.name): \(reason)" }
        if failed.allSatisfy({ $0.failure == first.failure }) {
            return "Couldn't upload \(failed.count) files: \(reason)"
        }
        return "Couldn't upload \(first.name) and \(failed.count - 1) more: \(reason)"
    }

    /// While the files go up: "Uploading photo.jpg…", or "Uploading 2 of 3 files…".
    static func progressText(index: Int, of count: Int, name: String) -> String {
        count == 1 ? "Uploading \(name)…" : "Uploading \(index + 1) of \(count) files…"
    }
}

/// What happened to one dropped file.
nonisolated struct TerminalRemoteDropOutcome: Equatable, Sendable {
    /// The file's name as it was sent.
    let name: String
    /// Where it arrived on the host; nil when it didn't.
    let remotePath: String?
    let failure: TerminalRemoteDropFailure?

    static func arrived(_ name: String, at path: String) -> Self {
        Self(name: name, remotePath: path, failure: nil)
    }

    static func failed(_ name: String, _ failure: TerminalRemoteDropFailure) -> Self {
        Self(name: name, remotePath: nil, failure: failure)
    }
}

/// Why a dropped file didn't arrive, in words that say what to do. The server's own error text
/// goes to the log.
nonisolated enum TerminalRemoteDropFailure: Error, Equatable, Sendable {
    case folderRefused
    case notAFolder(String)
    case noSafeUpload
    case tooLarge(UInt64)
    case connectionLost
    case didNotFinish
    case cancelled

    var reason: String {
        switch self {
        case .folderRefused:
            "the host refused the folder. Check that your account can write to ~/.cache."
        case .notAFolder(let path):
            "\(path) on the host is a file, not a folder. Move it aside, then drop again."
        case .noSafeUpload:
            "the host's SFTP server can't upload without risking an existing file. It needs OpenSSH's hardlink extension."
        case .tooLarge(let limit):
            "it's larger than the \(ByteCountFormatter.string(fromByteCount: Int64(clamping: limit), countStyle: .file)) upload limit."
        case .connectionLost:
            "the connection ended. Reconnect, then drop it again."
        case .didNotFinish:
            "the upload didn't finish. Try dropping it again."
        case .cancelled:
            "the upload was cancelled."
        }
    }
}

// MARK: - The log

/// The raw errors behind a drop's plain messages.
nonisolated enum TerminalRemoteDropLog {
    static let logger = Logger(subsystem: "sh.glas", category: "terminal-drop")

    static func uploadFailed(_ error: any Error) {
        logger.error("A file dropped on a terminal didn't upload: \(String(describing: error), privacy: .public)")
    }

    static func partialCopyRemains() {
        logger.notice("A dropped file arrived; a hidden partial copy stays in the drop folder until the weekly clean-up")
    }
}

// MARK: - The host: its drop folder, over one SFTP client

/// One drop's work on the host. The folders, the listing and the clean-up go over `client`; each
/// file goes up through `upload`, which is the Files browser's verified upload outside tests.
struct TerminalRemoteDropHost {
    /// Uploads `file` as `name` into `directory`, never replacing a file already there. Throws a
    /// `TerminalRemoteDropFailure`, or `CancellationError`.
    typealias Upload = @Sendable (
        _ client: SFTPClient, _ file: URL, _ serverID: UUID, _ directory: String, _ name: String, _ maximumBytes: UInt64
    ) async throws -> Void

    let client: SFTPClient
    let serverID: UUID
    let upload: Upload
    var maximumBytes: UInt64 = BoundedStorage.maximumUploadBytes

    private static var logger: Logger { TerminalRemoteDropLog.logger }

    /// The day's folder, made as needed, each folder down from the home folder in turn. The ones
    /// this app makes are for this account alone: a dropped photo is no one else's business.
    func prepareFolder(now: Date, timeZone: TimeZone) async throws -> (home: String, day: String) {
        let home: String
        do {
            home = try await client.getRealPath(atPath: ".")
        } catch {
            Self.logger.error("The home folder couldn't be resolved for a drop: \(String(describing: error), privacy: .public)")
            throw await connectionFailure(or: .folderRefused)
        }
        guard home.hasPrefix("/") else { throw TerminalRemoteDropFailure.folderRefused }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        var path = base
        var shown = "~"
        for component in TerminalRemoteDropPlan.folder.split(separator: "/").map(String.init)
            + [TerminalRemoteDropPlan.dayName(for: now, timeZone: timeZone)] {
            path += "/" + component
            shown += "/" + component
            try await ensureFolder(path, shownAs: shown)
        }
        return (home, path)
    }

    private func ensureFolder(_ path: String, shownAs shown: String) async throws {
        if let attributes = try? await client.getAttributes(at: path) {
            guard attributes.fileType == .directory else { throw TerminalRemoteDropFailure.notAFolder(shown) }
            return
        }
        do {
            try await client.createDirectory(atPath: path)
        } catch {
            // Another drop may have made it a moment ago.
            if let attributes = try? await client.getAttributes(at: path), attributes.fileType == .directory { return }
            Self.logger.error("A drop folder couldn't be made: \(String(describing: error), privacy: .public)")
            throw await connectionFailure(or: .folderRefused)
        }
        do {
            try await client.setAttributes(at: path, to: SFTPFileAttributes(permissions: 0o700))
        } catch {
            Self.logger.notice("A drop folder kept the host's default permissions: \(String(describing: error), privacy: .public)")
        }
    }

    /// Sends each file into `day` under a name nothing there has, in order. `progress` hears the
    /// index and name of each file as it starts.
    func send(
        _ files: [URL],
        into day: String,
        progress: (_ index: Int, _ name: String) -> Void = { _, _ in }
    ) async -> [TerminalRemoteDropOutcome] {
        var taken: Set<String>
        do {
            taken = Set(try await client.listDirectory(atPath: day).flatMap(\.components)
                .map { TerminalRemoteDropPlan.collisionKey($0.filename) })
        } catch {
            let failure = await connectionFailure(or: .folderRefused)
            return files.map { .failed($0.lastPathComponent, failure) }
        }
        var outcomes: [TerminalRemoteDropOutcome] = []
        for (index, file) in files.enumerated() {
            let name = TerminalRemoteDropPlan.uniqueName(
                TerminalRemoteDropPlan.remoteName(for: file.lastPathComponent), taken: &taken
            )
            guard !Task.isCancelled else {
                outcomes.append(.failed(name, .cancelled))
                continue
            }
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, UInt64(size) > maximumBytes {
                outcomes.append(.failed(name, .tooLarge(maximumBytes)))
                continue
            }
            progress(index, name)
            do {
                try await upload(client, file, serverID, day, name, maximumBytes)
                outcomes.append(.arrived(name, at: SFTPBrowserView.remotePath(directory: day, basename: name)))
            } catch is CancellationError {
                outcomes.append(.failed(name, .cancelled))
            } catch let failure as TerminalRemoteDropFailure {
                var reported = failure
                if failure == .didNotFinish { reported = await connectionFailure(or: failure) }
                outcomes.append(.failed(name, reported))
            } catch {
                Self.logger.error("A dropped file didn't upload: \(String(describing: error), privacy: .public)")
                outcomes.append(.failed(name, await connectionFailure(or: .didNotFinish)))
            }
        }
        return outcomes
    }

    /// Clears day folders older than a week from the drop folder, and nothing outside it. A link is
    /// never followed: only real folders are entered and only what is in them is removed. Quiet: a
    /// folder that can't be cleared waits for next time. Returns the day folders cleared.
    @discardableResult
    func clearExpired(home: String, now: Date, timeZone: TimeZone) async -> [String] {
        let root = TerminalRemoteDropPlan.root(home: home)
        guard let rootAttributes = try? await client.getLinkAttributes(at: root),
              rootAttributes.fileType == .directory,
              let listing = try? await client.listDirectory(atPath: root).flatMap(\.components) else { return [] }
        let folders = listing
            .filter { SFTPEntry.isSafeName($0.filename) && $0.attributes.fileType == .directory }
            .map(\.filename)
        var cleared: [String] = []
        for name in TerminalRemoteDropPlan.expiredDays(folders, now: now, timeZone: timeZone) {
            if await removeFolder(SFTPBrowserView.remotePath(directory: root, basename: name), depth: 0) {
                cleared.append(name)
            }
        }
        if !cleared.isEmpty {
            Self.logger.info("Cleared \(cleared.count, privacy: .public) week-old drop folders on the host")
        }
        return cleared
    }

    private func removeFolder(_ path: String, depth: Int) async -> Bool {
        guard depth < 8,
              let attributes = try? await client.getLinkAttributes(at: path),
              attributes.fileType == .directory,
              let entries = try? await client.listDirectory(atPath: path).flatMap(\.components) else { return false }
        var emptied = true
        for entry in entries {
            guard SFTPEntry.isSafeName(entry.filename) else { emptied = false; continue }
            let child = SFTPBrowserView.remotePath(directory: path, basename: entry.filename)
            if entry.attributes.fileType == .directory {
                let removed = await removeFolder(child, depth: depth + 1)
                if !removed { emptied = false }
            } else {
                // A file, or a link itself, never what a link points to.
                do { try await client.remove(at: child) } catch { emptied = false }
            }
        }
        guard emptied else { return false }
        do {
            try await client.rmdir(at: path)
            return true
        } catch {
            return false
        }
    }

    /// A failure is the connection's when the connection has gone.
    private func connectionFailure(or failure: TerminalRemoteDropFailure) async -> TerminalRemoteDropFailure {
        await client.isActive ? failure : .connectionLost
    }
}

// MARK: - HEIC to JPEG

/// Photos keeps photos as HEIC, which the tools that read a typed path often can't open (Claude
/// Code among them). A HEIC or HEIF image goes as JPEG; everything else goes as it is.
nonisolated enum TerminalDropImageConversion {
    static func isHEIC(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .heic) || type.conforms(to: .heif)
    }

    /// `url` as it is, or for a HEIC image a JPEG of it, written into a folder of its own in
    /// `folder` and named as the photo was, with `.jpg`.
    @concurrent
    static func uploadable(_ url: URL, writingInto folder: URL) async throws -> URL {
        guard isHEIC(url) else { return url }
        return try jpeg(from: url, into: folder)
    }

    /// Full size and upright: the pixels are turned as the photo's orientation says, and the
    /// orientation reset, so a tool that ignores the tag still sees the photo the right way up.
    /// The rest of the photo's metadata goes with it.
    static func jpeg(from source: URL, into folder: URL) throws -> URL {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(image) > 0,
              var metadata = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? Int,
              let height = metadata[kCGImagePropertyPixelHeight] as? Int else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        metadata[kCGImagePropertyOrientation] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        metadata[kCGImageDestinationLossyCompressionQuality] = 0.9

        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let output = directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, upright, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output
    }
}

// MARK: - Drops on terminals, by session

/// A drop's progress or problem, shown in the corner of the terminal it was dropped on.
struct TerminalRemoteDropStatus: Equatable {
    enum Kind: Equatable { case working, problem, notice }
    let kind: Kind
    let text: String
}

/// Every terminal's drops: one at a time per terminal, each in its own task, with its status where
/// the terminal can show it. A Mac's SSH pane and a Vision Pro window both come here.
@MainActor
@Observable
final class TerminalRemoteDrops {
    static let shared = TerminalRemoteDrops()

    /// Files from Files, photos from Photos, and any other app's files: anything that arrives as one
    /// regular file (`SFTPIncomingDrop.isReadableAsOneFile`).
    static let acceptedTypes: [String] = SFTPIncomingDrop.acceptedTypes + [UTType.data.identifier]

    private(set) var statuses: [UUID: TerminalRemoteDropStatus] = [:]

    @ObservationIgnored var openClient: (TerminalSession) async throws -> SFTPClient
    @ObservationIgnored var upload: TerminalRemoteDropHost.Upload
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var timeZone: TimeZone = .current
    @ObservationIgnored private var jobs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var statusExpiry: [UUID: Task<Void, Never>] = [:]
    /// Terminals whose connection has had its week-old drops cleared. One leaves the set when its
    /// connection ends, so the next connection clears again.
    @ObservationIgnored private(set) var clearedConnections: Set<UUID> = []

    private static var logger: Logger { TerminalRemoteDropLog.logger }

    init(
        openClient: @escaping (TerminalSession) async throws -> SFTPClient = TerminalRemoteDrops.openClient(for:),
        upload: @escaping TerminalRemoteDropHost.Upload = SFTPBrowserView.uploadDroppedFile
    ) {
        self.openClient = openClient
        self.upload = upload
    }

    static func openClient(for session: TerminalSession) async throws -> SFTPClient {
        guard let connection = session.getSSHConnection() else { throw SSHError.notConnected }
        return try await connection.openSFTPClient()
    }

    /// Types into the session's own terminal, as a paste: bracketed when the program asked for it.
    static func typeIntoTerminal(of session: TerminalSession) -> (String) -> Void {
        { [weak session] text in session?.terminalHostModel.insertDroppedText(text) }
    }

    // MARK: Receiving

    /// A drop of `providers` on a terminal (iPhone, iPad, Vision Pro). False when the terminal
    /// refuses it, which the system shows by sending the items back.
    @discardableResult
    func receive(_ providers: [NSItemProvider], on session: TerminalSession) -> Bool {
        // A dragged terminal tab (W15) is data too, and is never uploaded as a file.
        guard !TerminalTabTransfer.isCarried(by: providers),
              let drop = SFTPIncomingDrop(providers: providers) else { return false }
        return receive(drop, on: session, insert: Self.typeIntoTerminal(of: session))
    }

    /// A drop already read off the drag (a Mac reads the drag pasteboard as the drop happens).
    func receive(_ drop: SFTPIncomingDrop, on session: TerminalSession, insert: @escaping (String) -> Void) -> Bool {
        guard accepts(session) else { return false }
        start(on: session, insert: insert) { staging in
            try await drop.materialize(into: staging).urls
        }
        return true
    }

    /// Files already on this device.
    @discardableResult
    func receive(files: [URL], on session: TerminalSession, insert: @escaping (String) -> Void) -> Bool {
        guard !files.isEmpty, accepts(session) else { return false }
        start(on: session, insert: insert) { _ in files }
        return true
    }

    /// Waits for the terminal's drop to finish. Tests wait on it; the app never needs to.
    func waitForDrop(on sessionID: UUID) async {
        await jobs[sessionID]?.value
    }

    private func accepts(_ session: TerminalSession) -> Bool {
        guard session.purpose == .terminal, session.state == .connected,
              session.getSSHConnection() != nil else {
            show(TerminalRemoteDropStatus(kind: .notice, text: "Not connected. Reconnect, then drop again."), for: session.id)
            return false
        }
        // One drop at a time; the corner already says one is going up.
        return jobs[session.id] == nil
    }

    private func start(
        on session: TerminalSession,
        insert: @escaping (String) -> Void,
        receive: @escaping (SFTPDropStaging) async throws -> [URL]
    ) {
        let sessionID = session.id
        show(TerminalRemoteDropStatus(kind: .working, text: "Uploading…"), for: sessionID)
        jobs[sessionID] = Task { [weak self, weak session] in
            if let self, let session {
                await self.run(on: session, insert: insert, receive: receive)
            }
            self?.jobs[sessionID] = nil
        }
    }

    private func run(
        on session: TerminalSession,
        insert: (String) -> Void,
        receive: (SFTPDropStaging) async throws -> [URL]
    ) async {
        let sessionID = session.id
        // What the drop had to write, and any JPEG made on the way, stay until the uploads are done.
        let staging: SFTPDropStaging
        let received: [URL]
        do {
            staging = try SFTPDropStaging()
            received = try await receive(staging)
        } catch is CancellationError {
            show(TerminalRemoteDropStatus(kind: .notice, text: "Upload cancelled."), for: sessionID)
            return
        } catch {
            Self.logger.error("A drop on a terminal couldn't be read: \(String(describing: error), privacy: .public)")
            show(TerminalRemoteDropStatus(kind: .problem, text: "Couldn't read what was dropped. Try dropping it again."), for: sessionID)
            return
        }
        defer { withExtendedLifetime(staging) {} }
        guard !received.isEmpty else {
            clearStatus(for: sessionID)
            return
        }

        var files: [URL] = []
        /// Which of `files` stayed HEIC; the outcomes come back in the same order as the files.
        var unconverted: [Bool] = []
        for url in received {
            do {
                files.append(try await TerminalDropImageConversion.uploadable(url, writingInto: staging.directory))
                unconverted.append(false)
            } catch {
                Self.logger.error("A HEIC photo couldn't be converted to JPEG: \(String(describing: error), privacy: .public)")
                files.append(url)
                unconverted.append(true)
            }
        }

        let client: SFTPClient
        do {
            client = try await openClient(session)
        } catch {
            Self.logger.error("No SFTP channel for a drop: \(String(describing: error), privacy: .public)")
            let outcomes = files.map { TerminalRemoteDropOutcome.failed($0.lastPathComponent, .connectionLost) }
            finish(outcomes, unconverted: unconverted, on: sessionID, insert: insert)
            return
        }
        let host = TerminalRemoteDropHost(client: client, serverID: session.server.id, upload: upload)
        let now = now()
        do {
            let folder = try await host.prepareFolder(now: now, timeZone: timeZone)
            let count = files.count
            let outcomes = await host.send(files, into: folder.day) { [weak self] index, name in
                self?.show(TerminalRemoteDropStatus(
                    kind: .working,
                    text: TerminalRemoteDropPlan.progressText(index: index, of: count, name: name)
                ), for: sessionID)
            }
            finish(outcomes, unconverted: unconverted, on: sessionID, insert: insert)
            // After the paths are typed: nobody waits on it.
            if !Task.isCancelled, !clearedConnections.contains(sessionID) {
                clearedConnections.insert(sessionID)
                forgetClearingWhenDisconnected(session)
                await host.clearExpired(home: folder.home, now: now, timeZone: timeZone)
            }
        } catch {
            let failure = (error as? TerminalRemoteDropFailure) ?? .folderRefused
            finish(files.map { .failed($0.lastPathComponent, failure) }, unconverted: unconverted, on: sessionID, insert: insert)
        }
        do {
            try await client.close()
        } catch {
            Self.logger.notice("A drop's SFTP channel didn't close cleanly: \(String(describing: error), privacy: .public)")
        }
    }

    /// Types what arrived and says what didn't. A cancelled drop types nothing: cancelling means
    /// stop, and half a drop at the prompt is not what was asked for.
    private func finish(
        _ outcomes: [TerminalRemoteDropOutcome],
        unconverted: [Bool],
        on sessionID: UUID,
        insert: (String) -> Void
    ) {
        if Task.isCancelled || outcomes.contains(where: { $0.failure == .cancelled }) {
            show(TerminalRemoteDropStatus(kind: .notice, text: "Upload cancelled."), for: sessionID)
            return
        }
        if let text = TerminalRemoteDropPlan.typedText(for: outcomes) {
            insert(text)
        }
        var problems: [String] = []
        if let message = TerminalRemoteDropPlan.failureMessage(for: outcomes) { problems.append(message) }
        for (outcome, stayedHEIC) in zip(outcomes, unconverted) where stayedHEIC && outcome.remotePath != nil {
            problems.append("\(outcome.name) went as HEIC: it couldn't be converted to JPEG.")
        }
        if problems.isEmpty {
            clearStatus(for: sessionID)
        } else {
            show(TerminalRemoteDropStatus(kind: .problem, text: problems.joined(separator: " ")), for: sessionID)
        }
    }

    /// The next connection clears again: the session leaves the set once it is no longer connected.
    private func forgetClearingWhenDisconnected(_ session: TerminalSession) {
        withObservationTracking {
            _ = session.state
        } onChange: { [weak self, weak session] in
            Task { @MainActor in
                guard let self, let session else { return }
                if session.state == .connected {
                    self.forgetClearingWhenDisconnected(session)
                } else {
                    self.clearedConnections.remove(session.id)
                }
            }
        }
    }

    // MARK: Status

    func cancel(_ sessionID: UUID) {
        jobs[sessionID]?.cancel()
    }

    func dismiss(_ sessionID: UUID) {
        guard statuses[sessionID]?.kind != .working else { return }
        clearStatus(for: sessionID)
    }

    private func show(_ status: TerminalRemoteDropStatus, for sessionID: UUID) {
        statusExpiry[sessionID]?.cancel()
        statusExpiry[sessionID] = nil
        withAnimation(.easeInOut(duration: 0.2)) { statuses[sessionID] = status }
        let lifetime: Duration
        switch status.kind {
        case .working: return
        case .notice: lifetime = .seconds(4)
        case .problem: lifetime = .seconds(12)
        }
        statusExpiry[sessionID] = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self, self.statuses[sessionID] == status else { return }
            self.clearStatus(for: sessionID)
        }
    }

    private func clearStatus(for sessionID: UUID) {
        statusExpiry[sessionID]?.cancel()
        statusExpiry[sessionID] = nil
        withAnimation(.easeInOut(duration: 0.2)) { statuses[sessionID] = nil }
    }

    // MARK: Insert Path

    /// The terminal a Files browser belongs to: the browser's own session, when that session is a
    /// terminal. A browser opened from the library has an SFTP session of its own and no terminal.
    static func terminal(forBrowserSession id: UUID, in lookup: (UUID) -> TerminalSession?) -> TerminalSession? {
        guard let session = lookup(id), session.purpose == .terminal else { return nil }
        return session
    }

    /// Insert Path: types the remote `paths` at the terminal's cursor, escaped and space-separated
    /// with a trailing space, as a drop types them. False when there is no terminal or nothing to type.
    @discardableResult
    static func insertPaths(
        _ paths: [String],
        into terminal: TerminalSession?,
        type: (TerminalSession, String) -> Void = { $0.terminalHostModel.insertDroppedText($1) }
    ) -> Bool {
        guard let terminal, terminal.purpose == .terminal,
              let text = TerminalDroppedPaths.text(forPaths: paths) else { return false }
        type(terminal, text)
        return true
    }
}

// MARK: - Where a Mac pane's drop goes

/// A shell on this Mac reads this Mac's paths, so a drop on a local pane types them. Any other
/// shell is on a host: the files go there first, and the host's paths are typed (W14).
enum TerminalDropRoute {
    case localPaths(SwiftTermHostModel)
    case upload(TerminalSession)

    static func resolve(localModel: SwiftTermHostModel?, session: TerminalSession?) -> TerminalDropRoute? {
        if let localModel { return .localPaths(localModel) }
        if let session { return .upload(session) }
        return nil
    }
}

// MARK: - The terminal's corner

/// "Uploading 2 of 3 files…" while a drop goes up, or what went wrong, small, in the corner of the
/// terminal it was dropped on. The button cancels an upload or dismisses a message.
struct TerminalRemoteDropStatusView: View {
    let sessionID: UUID
    var drops = TerminalRemoteDrops.shared

    var body: some View {
        if let status = drops.statuses[sessionID] {
            HStack(alignment: .center, spacing: 8) {
                switch status.kind {
                case .working:
                    ProgressView().controlSize(.small)
                case .problem:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                case .notice:
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                Text(status.text)
                    .font(.caption)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if status.kind == .working { drops.cancel(sessionID) } else { drops.dismiss(sessionID) }
                } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(status.kind == .working ? "Cancel Upload" : "Dismiss")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 380, alignment: .trailing)
            .transition(.opacity)
        }
    }
}
