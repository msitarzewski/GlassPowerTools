//
//  TerminalLogFile.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  Which printed paths are logs: files a program writes as it goes, read from their end (the
//  owner, 2026-10-29, of a `.log` path in a terminal: "Should tail the output :)"). A log's preview
//  over the terminal shows its last lines and keeps up with them, its link menu leads with Watch
//  Log File, and from a server only its end is fetched.
//
//  By name: what developers' tools write. `.out` and `.err` are nohup's and a job's streams;
//  `.output` is what a log was once saved as here (2026-10-16); a rotated log keeps its name with a
//  number or a date after it (`app.log.1`, `app.log.2026-10-29`).
//

import Foundation

public enum TerminalLogFile {
    static let extensions: Set<String> = ["log", "out", "err", "stdout", "stderr", "output", "trace"]

    /// Whether `path` names a log, by its file's name.
    public static func isLog(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts[0].isEmpty || parts.count > 2 else { return false }
        if extensions.contains(String(parts[parts.count - 1])) { return true }
        // Rotated: the log's own extension, then a number or a date.
        guard parts.count >= 3 else { return false }
        let rotation = parts[parts.count - 1]
        return extensions.contains(String(parts[parts.count - 2]))
            && !rotation.isEmpty && rotation.allSatisfy { $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
