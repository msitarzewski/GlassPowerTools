//
//  VNCDiagnostics.swift
//  Glass Power Tools — VNCKit
//
//  Screen sharing's events, written to a small file in the app's own storage as well as to the
//  system log, so a session that went wrong on a headset can be read afterwards. A Vision Pro's
//  system log can't be collected over the network (`log collect --device-udid` answers "Device
//  not configured"), but the app's data container can be copied from it with `devicectl`:
//
//    xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
//      --domain-identifier com.glasspowertools \
//      --source Library/Caches/com.glasspowertools/Diagnostics/screen-sharing.log --destination <file>
//
//  What is written is what the `event=` log lines already say: connection attempts, the
//  displays and scale a Mac reports, what was asked of it and how a session ended. Never a
//  password, a credential or a picture. The file is capped; the previous one is kept beside it.
//

import Foundation
import os

public enum VNCDiagnostics {
    /// Off until the app switches it on at launch, so a test run never writes into the
    /// person's own Caches.
    private static let enabled = OSAllocatedUnfairLock(initialState: false)

    /// Starts keeping the file. The app calls it once, at launch.
    public static func enable() { enabled.withLock { $0 = true } }

    /// Where the log is kept: Caches, so the system may clear it and it is never backed up, in a
    /// folder named for the app — on the Mac, which runs outside the sandbox, Caches is the
    /// person's whole `~/Library/Caches`.
    public static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.glassdt", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("screen-sharing.log")
    }

    /// When the file passes this size it becomes `screen-sharing.1.log` and a new one starts.
    static let limit = 512 * 1024

    private static let queue = DispatchQueue(label: "app.glassdt.vnc.diagnostics")
    private static let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Logs `message` at `level` and appends it, with the time and `category`, to the file.
    public static func note(_ logger: Logger, _ level: OSLogType, category: String, _ message: String) {
        logger.log(level: level, "\(message, privacy: .public)")
        record(category: category, message)
    }

    /// Appends a line to the file, off the caller's thread.
    public static func record(category: String, _ message: String) {
        guard enabled.withLock({ $0 }) else { return }
        let line = "\(timestamp.format(Date())) \(category) \(message)\n"
        queue.async { append(Data(line.utf8)) }
    }

    private static func append(_ data: Data) {
        guard let url = fileURL else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: url.path)[.size]) as? Int, size > limit {
            let previous = url.deletingLastPathComponent().appendingPathComponent("screen-sharing.1.log")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
