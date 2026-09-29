//
//  TestDefaults.swift
//  Glass Power Tools — tests
//
//  Every defaults suite a test opens is removed, file and all, when the test process exits.
//
//  Tests opened a suite named with a fresh UUID and never removed it — and removing the domain
//  (`removePersistentDomain`) empties it but leaves its 42-byte plist behind. By 2026-09-28 the
//  developer's ~/Library/Preferences held about 34,000 of them. Tests call
//  `UserDefaults.forTest(suiteName:)` instead of `UserDefaults(suiteName:)`; the same copy of this
//  file lives in each test target that opens suites.
//

import Foundation

/// `nonisolated` because the exit handler runs outside any actor: a target that defaults to the
/// main actor made it main-actor-isolated, and the process trapped on exit (signal 5).
nonisolated enum TestDefaults {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: Set<String> = []
    nonisolated(unsafe) private static var armed = false
    nonisolated(unsafe) private static var swept: Set<String> = []

    static func register(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        names.insert(name)
        sweepEarlierRuns(of: name)
        guard !armed else { return }
        armed = true
        atexit { TestDefaults.removeAll() }
    }

    /// **Not only at exit.** `swift test` runs a target in more than one process, and not every
    /// one of them runs exit handlers, so some suites outlive the process that opened them. The
    /// first time a prefix is used, its files from earlier runs — at least ten minutes old, so a
    /// run in progress is never touched — are deleted. At most one run's worth can remain.
    private static func sweepEarlierRuns(of name: String) {
        guard let range = name.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                                     options: .regularExpression) else { return }
        let prefix = String(name[..<range.lowerBound])
        guard !prefix.isEmpty, swept.insert(prefix).inserted else { return }
        let preferences = preferencesDirectory
        let cutoff = Date().addingTimeInterval(-600)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: preferences, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "plist" {
            let stem = file.deletingPathExtension().lastPathComponent
            guard stem.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                             options: .regularExpression) != nil,
                  let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static var preferencesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    static func removeAll() {
        lock.lock()
        let all = names
        lock.unlock()
        let preferences = preferencesDirectory
        for name in all {
            UserDefaults.standard.removePersistentDomain(forName: name)
            CFPreferencesAppSynchronize(name as CFString)
        }
        // The preferences daemon writes an emptied domain's file back on its own schedule, so the
        // files are deleted after it has had its moment.
        if !all.isEmpty { Thread.sleep(forTimeInterval: 0.5) }
        for name in all {
            try? FileManager.default.removeItem(at: preferences.appendingPathComponent("\(name).plist"))
        }
    }
}

nonisolated extension UserDefaults {
    /// A suite for tests, removed with its file when the test process exits.
    static func forTest(suiteName name: String) -> UserDefaults? {
        TestDefaults.register(name)
        return UserDefaults(suiteName: name)
    }
}
