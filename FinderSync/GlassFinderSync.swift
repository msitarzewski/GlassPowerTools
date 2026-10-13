//
//  GlassFinderSync.swift
//  Glass Power Tools — Finder toolbar button
//
//  A button in every Finder window's toolbar (D72, 2026-10-13: the owner chose "all of the things",
//  a Finder toolbar button among them): New Glass Power Tools Tab Here, Window Here, and Open in
//  Glass Power Tools, for the folder the window shows or what is selected in it. A Finder Sync
//  extension, which the person adds to the toolbar (View ▸ Customize Toolbar…) after switching it
//  on in System Settings ▸ General ▸ Login Items & Extensions ▸ Finder.
//
//  Only the toolbar: Services and the Quick Action already put these in the Finder's right-click
//  menu, and a third copy there would be clutter. The extension runs sandboxed in its own process,
//  so it leaves its request in the App Group and opens the app (`GlassExternalRequests.send`).
//

import Cocoa
import FinderSync
import GlassWidgetData

final class GlassFinderSync: FIFinderSync {
    override init() {
        super.init()
        // Every folder: the button belongs in any Finder window.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String { "Glass Power Tools" }
    override var toolbarItemToolTip: String { "Open a terminal here, or open this in the editor" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "apple.terminal", accessibilityDescription: "Glass Power Tools") ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .toolbarItemMenu else { return nil }
        let menu = NSMenu(title: "Glass Power Tools")
        menu.addItem(withTitle: "New Glass Power Tools Tab Here", action: #selector(newTabHere(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Glass Power Tools Window Here", action: #selector(newWindowHere(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open in Glass Power Tools", action: #selector(openInGlassPowerTools(_:)), keyEquivalent: "")
        return menu
    }

    /// What the button acts on: the items selected, or else the folder the window shows.
    private var targets: [URL] {
        let controller = FIFinderSyncController.default()
        if let selected = controller.selectedItemURLs(), !selected.isEmpty { return selected }
        return controller.targetedURL().map { [$0] } ?? []
    }

    @objc func newTabHere(_ sender: AnyObject?) {
        guard let first = targets.first else { return }
        send(.newLocalTerminalTab(folder: first))
    }

    @objc func newWindowHere(_ sender: AnyObject?) {
        guard let first = targets.first else { return }
        send(.newLocalTerminal(folder: first))
    }

    @objc func openInGlassPowerTools(_ sender: AnyObject?) {
        let urls = targets
        guard !urls.isEmpty else { return }
        send(.openInEditor(urls))
    }

    private func send(_ request: GlassWidgetRequest) {
        MainActor.assumeIsolated {
            do {
                try GlassExternalRequests.send(request)
            } catch {
                NSSound.beep()
            }
        }
    }
}
