//
//  GlassQuickAction.swift
//  Glass Power Tools — Finder Quick Actions
//
//  Finder ▸ Quick Actions ▸ New Glass Power Tools Window Here and New Glass Power Tools Tab Here, in
//  the right-click menu and the preview pane (D72, 2026-10-13: Quick Actions as well as Services, "all
//  of the things"; the tab, 2026-11-01). The Finder lists one action per extension, so each is a target
//  of its own built from this folder, and `Info.plist` names its class (`GPT_QUICK_ACTION_CLASS`). A
//  file stands for its folder. No interface of its own, run sandboxed in its own process: it leaves the
//  request in the App Group and opens the app (`GlassExternalRequests.send`).
//

import AppKit
import UniformTypeIdentifiers
import GlassWidgetData

/// New Glass Power Tools Window Here.
class GlassQuickAction: NSObject, NSExtensionRequestHandling {
    /// A tab in the terminal window in front instead of a window of its own.
    class var opensTab: Bool { false }

    func beginRequest(with context: NSExtensionContext) {
        let providers = (context.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            context.cancelRequest(withError: CocoaError(.fileNoSuchFile))
            return
        }
        nonisolated(unsafe) let context = context
        let opensTab = Self.opensTab
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let url, url.isFileURL else {
                        context.cancelRequest(withError: CocoaError(.fileNoSuchFile))
                        return
                    }
                    do {
                        try GlassExternalRequests.send(opensTab ? .newLocalTerminalTab(folder: url) : .newLocalTerminal(folder: url))
                        context.completeRequest(returningItems: nil)
                    } catch {
                        context.cancelRequest(withError: error)
                    }
                }
            }
        }
    }
}

/// New Glass Power Tools Tab Here: a window when no terminal window is open.
final class GlassQuickTabAction: GlassQuickAction {
    override class var opensTab: Bool { true }
}
