//
//  TerminalDroppedPaths.swift
//  Glass Power Tools — GlassTerminal
//
//  Files dropped on a terminal become their paths at the prompt, as Terminal.app does
//  (2026-10-07: "I can't drag an image from Finder into the terminal and have it land as a path").
//  Each path is escaped for the shell, the paths are separated by spaces, and a trailing space
//  leaves the cursor ready for the next word. Nothing is run: the text is typed, not entered.
//

import Foundation

enum TerminalDroppedPaths {
    /// The app's own folder in the user's caches, for files a drop had to write.
    static let inboxName = "Dropped"

    /// Where a dropped file that exists nowhere yet is written. A screenshot dragged from its
    /// floating thumbnail is a file promise, written only when the drop says where (2026-10-09:
    /// "I really do need to be able to drag screen shots taken with shift-command-4 … into a
    /// terminal window"); so is an image dragged as bare data. The path is typed into the shell and
    /// read later — by an agent, often — so the file stays. Each drop has a folder of its own, and
    /// folders older than a week are cleared the next time something is dropped.
    static func inbox(caches: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                      now: Date = Date(), fileManager: FileManager = .default) throws -> URL {
        guard let caches else { throw CocoaError(.fileNoSuchFile) }
        let inbox = caches.appendingPathComponent("com.glasspowertools", isDirectory: true)
            .appendingPathComponent(inboxName, isDirectory: true)
        try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let folders = (try? fileManager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for folder in folders {
            if let created = try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate, created < cutoff {
                try? fileManager.removeItem(at: folder)
            }
        }
        return inbox
    }

    /// The text a drop of `urls` types. File URLs only; anything else is left out.
    static func text(for urls: [URL]) -> String? {
        let paths = urls.filter(\.isFileURL).map { escaped($0.path) }
        return paths.isEmpty ? nil : paths.joined(separator: " ") + " "
    }

    /// A path as a shell reads it back unchanged. Letters, digits and `_./-+,:@%^=` stand as they
    /// are; anything else is backslash-escaped, as Terminal.app writes a dropped path. A control
    /// character — a newline in a file name — cannot be backslash-escaped, so that path is written
    /// in `$'…'` form instead, which bash, zsh and fish all read.
    static func escaped(_ path: String) -> String {
        if path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            var body = ""
            for scalar in path.unicodeScalars {
                switch scalar {
                case "\\": body += "\\\\"
                case "'": body += "\\'"
                case "\n": body += "\\n"
                case "\t": body += "\\t"
                case "\r": body += "\\r"
                default:
                    if CharacterSet.controlCharacters.contains(scalar) {
                        body += String(format: "\\x%02x", scalar.value)
                    } else {
                        body.unicodeScalars.append(scalar)
                    }
                }
            }
            return "$'" + body + "'"
        }
        var result = ""
        for scalar in path.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || "_./-+,:@%^=".unicodeScalars.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result += "\\"
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
