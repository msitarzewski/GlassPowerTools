//
//  GlassFinderServices.swift
//  Glass Power Tools
//
//  Finder ▸ Services (D72, 2026-10-13 — the owner's screenshot of Finder's Services menu, beside
//  Ghostty's and iTerm2's): New Glass Power Tools Tab Here, New Glass Power Tools Window Here, and
//  Open in Glass Power Tools. Declared in the Mac's Info.plist (`NSServices`) as Ghostty, iTerm2
//  and CotEditor declare theirs — a file-path context and filenames or text — and carried out as
//  Siri's requests are. A file stands for the folder it is in, for a terminal; Open in Glass Power
//  Tools opens files in the editor and a folder as a project.
//

#if os(macOS)
import AppKit
import GlassWidgetData

final class GlassFinderServices: NSObject {
    @objc func newTabHere(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let first = Self.paths(on: pasteboard).first else { return Self.fail(error) }
        MainActor.assumeIsolated { GlassWidgetRequests.shared.post(.newLocalTerminalTab(folder: first)) }
    }

    @objc func newWindowHere(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let first = Self.paths(on: pasteboard).first else { return Self.fail(error) }
        MainActor.assumeIsolated { GlassWidgetRequests.shared.post(.newLocalTerminal(folder: first)) }
    }

    @objc func openInGlassPowerTools(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        let urls = Self.paths(on: pasteboard)
        guard !urls.isEmpty else { return Self.fail(error) }
        MainActor.assumeIsolated { GlassWidgetRequests.shared.post(.openInEditor(urls)) }
    }

    /// The files the Finder handed over: as file URLs, as the old filenames list, or as text with
    /// one absolute path per line. Only paths that exist.
    static func paths(on pasteboard: NSPasteboard) -> [URL] {
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty,
           let names = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = names.map { URL(fileURLWithPath: $0) }
        }
        if urls.isEmpty, let text = pasteboard.string(forType: .string) {
            urls = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("/") }
                .map { URL(fileURLWithPath: $0) }
        }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func fail(_ error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        error?.pointee = "Choose a file or folder in the Finder, then try again." as NSString
    }
}
#endif
