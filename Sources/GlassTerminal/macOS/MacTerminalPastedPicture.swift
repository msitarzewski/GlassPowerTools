//
//  MacTerminalPastedPicture.swift
//  Glass Power Tools — GlassTerminal
//
//  A picture pasted on a Mac terminal goes where a dropped one goes (2026-11-06: "No surprises for users (like
//  not being able to paste an image into the terminal)"). ⌘V read text alone, so a screenshot copied to the
//  clipboard pasted nothing, where iPhone, iPad and Vision Pro have uploaded it since 2026-10-25.
//
//  - An SSH pane: uploaded to the host's drop folder and the host's path typed (`TerminalRemoteDrops`), as a drop.
//  - A local pane: written to this Mac's drop folder and its path typed (`TerminalDroppedPaths`), as a drop.
//    Claude Code takes a typed picture path as the picture, as it takes a dragged one.
//
//  Only a clipboard that holds a picture and nothing a terminal could type: a screenshot, Copy Image from Preview,
//  Safari or Photos. Text beside a picture is pasted as text, as before: Excel, Numbers and Word copy a picture of
//  the cells along with their text, and the text is what a terminal wants. A file copied in the Finder pastes as it
//  did. Other terminals send an empty paste for a picture and leave the program to read the clipboard itself
//  (Claude Code reads it on this Mac, never over SSH); a path works for every program, here and on a host.
//

#if os(macOS)
import AppKit
import Foundation
import GlassTerminalEmulator
import UniformTypeIdentifiers
import os

@MainActor
enum MacTerminalPastedPicture {
    private static let logger = Logger(subsystem: "sh.glas", category: "terminal-paste")

    /// The picture on `pasteboard` as PNG, ready to be received as a paste; nil when it holds text or a file (the
    /// paste is typed as before), or no picture.
    static func providers(on pasteboard: NSPasteboard = .general) -> [NSItemProvider]? {
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return nil }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return nil }
        guard let png = pngData(on: pasteboard) else { return nil }
        return [NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)]
    }

    /// PNG as copied, else the picture redrawn as PNG: a TIFF (what Preview and Photos copy) is a type Claude Code
    /// and most programs don't read.
    static func pngData(on pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty { return png }
        guard NSImage.canInit(with: pasteboard), let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// An SSH pane's paste: the picture uploaded and the host's path typed. False when the clipboard holds none.
    static func paste(on session: TerminalSession, pasteboard: NSPasteboard = .general) -> Bool {
        guard let providers = providers(on: pasteboard) else { return false }
        logger.notice("event=paste-picture route=upload")
        return TerminalRemoteDrops.shared.receive(pasted: providers, on: session,
                                                  insert: TerminalRemoteDrops.typeIntoTerminal(of: session))
    }

    /// A local pane's paste: the picture written to this Mac's drop folder and its path typed. False when the
    /// clipboard holds none.
    static func paste(into model: SwiftTermHostModel, pasteboard: NSPasteboard = .general) -> Bool {
        guard let providers = providers(on: pasteboard), let drop = SFTPIncomingDrop(pasted: providers) else { return false }
        logger.notice("event=paste-picture route=local")
        Task { @MainActor [weak model] in
            do {
                let staging = try SFTPDropStaging(keepingFilesIn: TerminalDroppedPaths.inbox())
                let received = try await drop.materialize(into: staging)
                guard let text = TerminalDroppedPaths.text(for: received.urls), let model else {
                    logger.error("event=paste-picture-untyped files=\(received.urls.count, privacy: .public)")
                    NSSound.beep()
                    return
                }
                _ = model.insertDroppedText(text)
            } catch {
                logger.error("A picture pasted on a terminal could not be written: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
        return true
    }
}
#endif
