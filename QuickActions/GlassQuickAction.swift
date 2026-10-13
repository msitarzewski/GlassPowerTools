//
//  GlassQuickAction.swift
//  Glass Power Tools — Finder Quick Action
//
//  Finder ▸ Quick Actions ▸ New Glass Power Tools Window Here, in the right-click menu and the
//  preview pane (D72, 2026-10-13: Quick Actions as well as Services, "all of the things"). A file
//  stands for its folder. An action extension with no interface of its own, run sandboxed in its own
//  process: it leaves the request in the App Group and opens the app (`GlassExternalRequests.send`).
//

import AppKit
import UniformTypeIdentifiers
import GlassWidgetData

final class GlassQuickAction: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let providers = (context.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            context.cancelRequest(withError: CocoaError(.fileNoSuchFile))
            return
        }
        nonisolated(unsafe) let context = context
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let url, url.isFileURL else {
                        context.cancelRequest(withError: CocoaError(.fileNoSuchFile))
                        return
                    }
                    do {
                        try GlassExternalRequests.send(.newLocalTerminal(folder: url))
                        context.completeRequest(returningItems: nil)
                    } catch {
                        context.cancelRequest(withError: error)
                    }
                }
            }
        }
    }
}
