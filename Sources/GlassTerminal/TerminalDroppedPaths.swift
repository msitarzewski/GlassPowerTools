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
