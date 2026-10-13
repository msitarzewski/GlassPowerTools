//
//  GlassExternalRequests.swift
//  Glass Power Tools — GlassWidgetData
//
//  Requests an extension in another process leaves for the app (D72, 2026-10-13): the Finder's
//  toolbar button and Quick Actions, which run in their own sandboxed processes and cannot call
//  into the app. Each writes its request into the App Group container the widgets already share,
//  then opens the app; the app takes what is waiting whenever it comes forward and carries it out
//  as it does Siri's (`GlassWidgetRequests`).
//
//  One file per request, named so they sort oldest first. A request older than a minute is
//  dropped unread — it was meant for a moment that has passed — so a stray file can never open a
//  window days later.
//

import Foundation
import os

public enum GlassExternalRequests {
    /// How long a request waits for the app.
    public static let lifetime: TimeInterval = 60

    static let logger = Logger(subsystem: "sh.glas", category: "external-requests")

    public static func folder(appGroup: String = GlassWidgetStore.appGroup, fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Requests", isDirectory: true)
    }

    /// Leaves `request` for the app.
    public static func leave(_ request: GlassWidgetRequest, in folder: URL? = folder(), now: Date = Date()) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = String(format: "%.6f", now.timeIntervalSince1970) + "-" + UUID().uuidString + ".json"
        try JSONEncoder().encode(request).write(to: folder.appendingPathComponent(name), options: [.atomic])
    }

    /// Everything waiting, oldest first, removed as it is taken; stale and unreadable ones are
    /// removed and left out.
    public static func take(from folder: URL? = folder(), now: Date = Date()) -> [GlassWidgetRequest] {
        guard let folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        var taken: [GlassWidgetRequest] = []
        for name in names.filter({ $0.hasSuffix(".json") }).sorted() {
            let file = folder.appendingPathComponent(name)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let stamp = name.split(separator: "-", maxSplits: 1).first.flatMap({ Double($0) }),
                  now.timeIntervalSince1970 - stamp <= lifetime else {
                logger.notice("A request too old to carry out was dropped")
                continue
            }
            do {
                taken.append(try JSONDecoder().decode(GlassWidgetRequest.self, from: Data(contentsOf: file)))
            } catch {
                logger.error("A request could not be read: \(String(describing: error), privacy: .public)")
            }
        }
        return taken
    }
}
