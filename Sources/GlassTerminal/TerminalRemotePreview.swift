//
//  TerminalRemotePreview.swift
//  Glass Power Tools — GlassTerminal
//
//  A file on a terminal's host, copied to this device for its preview over the terminal
//  (`TerminalPreviewFile`, the owner, 2026-10-16: "build it with the menu item and space, local and
//  remote"). Over the terminal's own SSH connection, as a file dropped on it goes up
//  (`TerminalRemoteDrops.openClient`), into a folder of its own that goes when the preview closes.
//

import Foundation
import os
import NIOCore
import NIOFoundationCompat
import GlassSSHTransport
import GlassTerminalEmulator

enum TerminalRemotePreview {
    /// A preview fetches no more than this: a large picture or PDF, not a disk image.
    static let byteLimit: UInt64 = 32 * 1024 * 1024

    /// The file at `path` — absolute, on `session`'s host — copied here, or nil when it can't be
    /// read, isn't a regular file, or is larger than `byteLimit`.
    static func fetch(_ path: String, from session: TerminalSession) async -> TerminalPreviewFile? {
        let client: SFTPClient
        do {
            client = try await TerminalRemoteDrops.openClient(for: session)
        } catch {
            Logger.pathPreview.error("event=fetch result=sftp-unavailable error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = await read(path, through: client)
        try? await client.close()
        guard let data else { return nil }
        return save(data, named: (path as NSString).lastPathComponent)
    }

    private static func read(_ path: String, through client: SFTPClient) async -> Data? {
        let size: UInt64?
        do {
            size = try await client.getAttributes(at: path).size
        } catch {
            Logger.pathPreview.error("event=fetch result=stat-failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let size, size <= byteLimit else {
            Logger.pathPreview.notice("event=fetch result=too-large size=\(size ?? 0, privacy: .public)")
            return nil
        }
        do {
            let file = try await client.openFile(filePath: path, flags: .read)
            let buffer = try? await file.readAll()
            try? await file.close()
            guard let buffer, UInt64(buffer.readableBytes) <= byteLimit else {
                Logger.pathPreview.error("event=fetch result=read-failed")
                return nil
            }
            return Data(buffer: buffer)
        } catch {
            Logger.pathPreview.error("event=fetch result=open-failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Into a folder of its own in the caches, under its own name, so a viewer that goes by the
    /// name — Quick Look does — sees what it is.
    /// - Parameter caches: the caches folder; the user's, unless a test gives one of its own.
    static func save(_ data: Data, named name: String,
                     caches: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        -> TerminalPreviewFile? {
        let manager = FileManager.default
        guard let caches, !name.isEmpty else { return nil }
        let folder = caches.appending(path: "GlassTerminalPreviews", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: name)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            try? manager.removeItem(at: folder)
            return nil
        }
        return TerminalPreviewFile(url: url) { try? FileManager.default.removeItem(at: folder) }
    }
}
