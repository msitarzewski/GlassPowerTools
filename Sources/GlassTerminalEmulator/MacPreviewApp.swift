//
//  MacPreviewApp.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  Open in Preview, beside Open in Editor, for a printed path to a file the Mac's Preview opens
//  (the owner, 2026-10-29: "I'd also like 'Open in Preview' in addition to Open in Editor for
//  image/mime types Preview can see"). Which those are is Launch Services' answer, not a list kept
//  here: Preview's own document types, as this Mac has them — pictures, PDFs, PostScript.
//

#if !canImport(UIKit) && canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

@MainActor
public enum MacPreviewApp {
    static let bundleIdentifier = "com.apple.Preview"

    /// Preview, where this Mac has it.
    public static var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// Answers by extension, asked once each: a menu is built at every right-click.
    private static var answers: [String: Bool] = [:]

    /// Whether Preview opens the file `path` names, by its extension.
    public static func opens(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if let known = answers[ext] { return known }
        var opens = false
        if let type = UTType(filenameExtension: ext), let preview = url?.standardizedFileURL {
            opens = NSWorkspace.shared.urlsForApplications(toOpen: type).contains { $0.standardizedFileURL == preview }
        }
        answers[ext] = opens
        return opens
    }

    /// Opens `file`, a file on this Mac, in Preview.
    public static func open(_ file: URL) {
        guard let url else {
            NSWorkspace.shared.open(file)
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
#endif
