//
//  TerminalPathPreview.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A file a terminal printed the path of, shown over the terminal in a popover (the owner,
//  2026-10-16: "Is there a world where we could resolve, say a path to a local image, and display
//  that image in a popover over the terminal? or markdown, or any of the file types supported by
//  our Editor?"). On this Mac or on the machine the terminal is on. Quick Look on a path's
//  right-click menu, and, as the setting says, the pointer resting on a path or Space while it does
//  ("Show previews: ( ) Never (•) Mouseover ( ) Mouseover + space").
//

import Foundation

/// When the file a printed path names shows by itself, under the pointer. Quick Look on a path's
/// right-click menu shows it whatever this says.
public enum TerminalPathPreviews: String, CaseIterable, Sendable {
    case never
    /// The pointer resting on a path shows its file. A web address never shows anything this way.
    case mouseover
    /// Space with the pointer on a path shows its file; on a web address, Space asks to open it, as
    /// a ⌘-click does (the owner: "They should require risk acceptance as we do now and the space
    /// can trigger that"). Space anywhere else types a space.
    case mouseoverAndSpace

    public var title: String {
        switch self {
        case .never: "Never"
        case .mouseover: "Mouseover"
        case .mouseoverAndSpace: "Mouseover + Space"
        }
    }
}

/// A file to preview, on this Mac: the file itself, or a copy fetched from the machine the terminal
/// is on, which `discard` removes once the preview closes.
public struct TerminalPreviewFile {
    public let url: URL
    public let discard: (@MainActor () -> Void)?

    public init(url: URL, discard: (@MainActor () -> Void)? = nil) {
        self.url = url
        self.discard = discard
    }
}
