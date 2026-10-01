//
//  DesktopPasteboard.swift
//  Glass Power Tools — GlassDesktop
//
//  The local clipboard as a remote desktop sees it (D42a, 2026-09-30): text, HTML, RTF and an image,
//  read and written in one place for every platform.
//

import Foundation
import SwiftUI
import GlassRDPTransport
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
enum DesktopPasteboard {
    /// What is on the clipboard now. On iPhone, iPad and Vision Pro this may ask permission, so
    /// it is only called when someone chooses Send Clipboard.
    static func read() -> GlassClipboardContent? {
        #if os(macOS)
        let board = NSPasteboard.general
        var content = GlassClipboardContent(text: board.string(forType: .string),
                                            html: board.string(forType: .html),
                                            rtf: board.data(forType: .rtf))
        if let png = board.data(forType: .png) {
            content.png = png
        } else if let tiff = board.data(forType: .tiff), let image = NSBitmapImageRep(data: tiff) {
            content.png = image.representation(using: .png, properties: [:])
        }
        #else
        let board = UIPasteboard.general
        var content = GlassClipboardContent(text: board.string)
        if let html = board.data(forPasteboardType: UTType.html.identifier) {
            content.html = String(data: html, encoding: .utf8)
        }
        content.rtf = board.data(forPasteboardType: UTType.rtf.identifier)
        content.png = board.data(forPasteboardType: UTType.png.identifier) ?? board.image?.pngData()
        #endif
        return content.isEmpty ? nil : content
    }

    /// Puts a remote copy on the local clipboard, every form at once.
    static func write(_ content: GlassClipboardContent) {
        guard !content.isEmpty else { return }
        #if os(macOS)
        let board = NSPasteboard.general
        board.clearContents()
        if let text = content.text { board.setString(text, forType: .string) }
        if let html = content.html { board.setString(html, forType: .html) }
        if let rtf = content.rtf { board.setData(rtf, forType: .rtf) }
        if let png = content.png { board.setData(png, forType: .png) }
        #else
        var item: [String: Any] = [:]
        if let text = content.text { item[UTType.utf8PlainText.identifier] = text }
        if let html = content.html { item[UTType.html.identifier] = Data(html.utf8) }
        if let rtf = content.rtf { item[UTType.rtf.identifier] = rtf }
        if let png = content.png { item[UTType.png.identifier] = png }
        UIPasteboard.general.setItems([item])
        #endif
    }

    #if os(macOS)
    /// Changes whenever anything is copied, here or in another app.
    static var changeCount: Int { NSPasteboard.general.changeCount }
    #endif
}

/// Keeps the two clipboards in step while a desktop is open, when clipboard sharing is on:
/// a copy made on the remote machine lands on this device's clipboard, on every platform; and on a
/// Mac, a copy made here reaches the remote machine when its window becomes active and whenever the
/// clipboard changes while it is. iPhone, iPad and Vision Pro send with Send Clipboard, because
/// reading another app's copy there asks permission each time.
struct DesktopClipboardBridge: ViewModifier {
    let session: DesktopSessionModel
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    /// The clipboard's change count when it was last sent, or last written from the remote side,
    /// so a remote copy is not sent straight back.
    @State private var settledChangeCount = -1
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: session.remoteClipboard) { _, copy in
                guard let copy, session.connection.clipboardEnabled else { return }
                DesktopPasteboard.write(copy)
                #if os(macOS)
                settledChangeCount = DesktopPasteboard.changeCount
                #endif
            }
            #if os(macOS)
            .task(id: appearsActive && session.isConnected && session.connection.clipboardEnabled) {
                guard appearsActive, session.isConnected, session.connection.clipboardEnabled else { return }
                while !Task.isCancelled {
                    let count = DesktopPasteboard.changeCount
                    if count != settledChangeCount {
                        settledChangeCount = count
                        if let local = DesktopPasteboard.read() { session.pasteClipboard(local) }
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            #endif
    }
}
