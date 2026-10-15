//
//  TerminalLinkLookup.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  The link under a cell, and what can be done with it, on every platform: the Mac's right-click
//  menu (`MacTerminalContextMenu`) and, on Vision Pro, a pinch held on a link without moving (the
//  owner, 2026-10-15: "the vision pro needs the data detector and selection work").
//

import Foundation
import SwiftTerm
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum TerminalLinkLookup {
    /// What the link at `position` — a cell of the buffer, scrollback counted — points at:
    /// SwiftTerm's link there, a hyperlink or text its rules recognise, across a soft-wrapped line
    /// too; or else an address Apple's detector finds on that row.
    static func target(at position: Position, in terminal: Terminal) -> TerminalLinkTarget? {
        if let text = terminal.link(at: .buffer(position), mode: .explicitAndImplicit) {
            return TerminalLinkTarget(link: text)
        }
        let screenRow = position.row - terminal.buffer.yDisp
        guard let line = terminal.getLine(row: screenRow)?.translateToString(trimRight: true),
              let url = TerminalLinkTarget.address(in: line, at: position.col) else { return nil }
        return .url(url)
    }

    /// The actions on a link, by name, as the Mac's menu offers them: Open Link and Copy Link on an
    /// address; Open in Editor, Show in Files, Watch Log File and Copy Path on a path, each only
    /// where the model's host can do it.
    struct Action {
        let title: String
        let symbol: String
        let perform: @MainActor () -> Void
    }

    static func actions(for target: TerminalLinkTarget, model: SwiftTermHostModel?,
                        copy: @escaping @MainActor (String) -> Void) -> [Action] {
        switch target {
        case .url(let url):
            let link = url.absoluteString
            var actions: [Action] = []
            // Only what a ⌘-click may open, a web address with no account in it, after the same question.
            if let model, SwiftTermExternalLinkPolicy.validatedRequest(for: link) != nil {
                actions.append(Action(title: "Open Link", symbol: "safari") { model.requestExternalLink(link) })
            }
            actions.append(Action(title: "Copy Link", symbol: "link") { copy(link) })
            return actions
        case .path(let path):
            var actions: [Action] = []
            if let open = model?.onOpenPath {
                actions.append(Action(title: "Open in Editor", symbol: "pencil.and.list.clipboard") { open(path) })
            }
            if let reveal = model?.onRevealPath, let title = model?.revealPathTitle {
                actions.append(Action(title: title, symbol: "folder") { reveal(path) })
            }
            if let watch = model?.onWatchFile, !path.hasSuffix("/") {
                actions.append(Action(title: "Watch Log File", symbol: "doc.text.magnifyingglass") { watch(path) })
            }
            actions.append(Action(title: "Copy Path", symbol: "doc.on.doc") { copy(path) })
            return actions
        }
    }

    #if canImport(UIKit)
    /// The same, as an edit menu's items.
    static func menuElements(for target: TerminalLinkTarget, model: SwiftTermHostModel?) -> [UIMenuElement] {
        actions(for: target, model: model, copy: { UIPasteboard.general.string = $0 }).map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.symbol)) { _ in action.perform() }
        }
    }
    #endif
}
