//
//  TerminalWatchFile.swift
//  Glass Power Tools — GlassTerminal
//
//  Watch Log File (the owner, 2026-10-14: "I'd like to detect a local path to a log (for example)
//  and offer a right click > watch log file that opens a new tab in the current window"): what
//  the new tab's shell runs, and what the tab is called. The tab is made where the path was
//  printed — this Mac, or the same host over a connection of its own (`MacWorkspaceController`).
//

import Foundation

enum TerminalWatchFile {
    /// `tail -F` on `path` as a terminal printed it, for a new shell on the same machine: `~/…`
    /// and `$VAR/…` left for that shell to expand, the rest escaped as a dropped path is, and a
    /// relative path made absolute against `directory`, the folder of the shell that printed it.
    /// `-F` follows the name rather than the open file, so a log that is rotated, or is not there
    /// yet, is picked up when it comes. Nil for a folder, or a relative path with no folder known.
    static func command(for path: String, in directory: String?) -> String? {
        guard !path.isEmpty, !path.hasSuffix("/") else { return nil }
        if path.hasPrefix("~/") {
            return "tail -F ~/" + TerminalDroppedPaths.escaped(String(path.dropFirst(2)))
        }
        if let variable = variablePrefix(of: path) {
            return "tail -F " + variable + TerminalDroppedPaths.escaped(String(path.dropFirst(variable.count)))
        }
        if path.hasPrefix("/") {
            return "tail -F " + TerminalDroppedPaths.escaped(path)
        }
        guard let directory, directory.hasPrefix("/") else { return nil }
        let absolute = NSString(string: (directory as NSString).appendingPathComponent(path)).standardizingPath
        return "tail -F " + TerminalDroppedPaths.escaped(absolute)
    }

    /// Whether `path` means something only beside the folder its shell was in.
    static func isRelative(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.hasPrefix("~/") && variablePrefix(of: path) == nil
    }

    /// The tab's name: the file's own.
    static func tabLabel(for path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// `$HOME/` in `$HOME/logs/app.log`: a variable for the shell, and the slash after it.
    private static func variablePrefix(of path: String) -> String? {
        guard path.hasPrefix("$"), let slash = path.firstIndex(of: "/") else { return nil }
        let name = path[path.index(after: path.startIndex)..<slash]
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter),
              name.allSatisfy({ $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }) else { return nil }
        return String(path[...slash])
    }
}

/// A path a terminal printed, made absolute on the machine it was printed on (the owner,
/// 2026-10-14: "open a path with a context menu"): `~/…` against that machine's home, a relative
/// path against the folder its shell was in. What only a shell can expand — `$VAR/…` — is not
/// guessed at: Copy Path and Watch Log File, which hand it to a shell, still take it.
enum TerminalPathResolution {
    static func absolute(_ path: String, directory: String?, home: String?) -> String? {
        guard !path.isEmpty, !path.hasPrefix("$") else { return nil }
        let joined: String
        if path.hasPrefix("/") {
            joined = path
        } else if path == "~" || path.hasPrefix("~/") {
            guard let home, home.hasPrefix("/") else { return nil }
            joined = (home as NSString).appendingPathComponent(String(path.dropFirst(path == "~" ? 1 : 2)))
        } else {
            guard let directory, directory.hasPrefix("/") else { return nil }
            joined = (directory as NSString).appendingPathComponent(path)
        }
        let standardized = NSString(string: joined).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }

    /// The folder Files or the Finder shows for `path`: the folder itself, or the one a file is in.
    static func folder(of path: String, isDirectory: Bool) -> String {
        isDirectory ? path : (path as NSString).deletingLastPathComponent
    }
}
