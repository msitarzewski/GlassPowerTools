//
//  TerminalCommandHistory.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): the commands run on each machine, kept so a terminal can offer them again.
//  `tasks/2026-11/2026-11-06_type-ahead.md`, "Privacy": on this device only (no iCloud), one file per machine with
//  complete file protection, excluded from backup, at most `limit` commands each. Nothing that looks like it carries
//  a secret is kept (`TerminalCommandSecrets`), nor a command typed with a space first (zsh's and bash's own sign).
//

import Foundation
import os

/// One command as run on a machine.
nonisolated struct TerminalCommandRecord: Codable, Equatable, Sendable {
    var command: String
    var count: Int
    var lastUsed: Date
    /// Folders it ran in, by how often (the most used few).
    var folders: [String: Int]
    /// Commands run just before it, by how often (the most frequent few): what usually comes next.
    var after: [String: Int]
    /// Its last exit status, where the shell gave one.
    var lastStatus: Int?
    /// Read from the machine's own history file rather than seen run here.
    var imported: Bool

    init(command: String, count: Int = 1, lastUsed: Date, folders: [String: Int] = [:], after: [String: Int] = [:],
         lastStatus: Int? = nil, imported: Bool = false) {
        self.command = command
        self.count = count
        self.lastUsed = lastUsed
        self.folders = folders
        self.after = after
        self.lastStatus = lastStatus
        self.imported = imported
    }
}

/// The commands run on each machine. One per app; tests make their own with a folder of their own.
@MainActor
final class TerminalCommandHistory {
    static let shared = TerminalCommandHistory(folder: TerminalCommandHistory.defaultFolder())

    /// The most commands kept for one machine; the least used and oldest go first.
    nonisolated static let limit = 5_000
    /// The most folders and following commands kept on one record.
    nonisolated static let detailLimit = 8
    /// The machine key for this Mac's own terminals.
    nonisolated static let thisMac = "this-mac"

    private nonisolated static let logger = Logger(subsystem: "sh.glas", category: "command-history")

    private let folder: URL?
    private var loaded: [String: [String: TerminalCommandRecord]] = [:]
    /// The last command recorded on each machine, for `after` and its exit status.
    private var lastRecorded: [String: String] = [:]
    private var pendingSaves: Set<String> = []
    private var saveTask: Task<Void, Never>?

    /// - Parameter folder: where each machine's file goes; nil keeps everything in memory (previews).
    init(folder: URL?) {
        self.folder = folder
    }

    /// Application Support's own folder, or the UI test run's, so a test run never reads or writes the person's.
    nonisolated static func defaultFolder() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var base = support.appendingPathComponent("Glass Power Tools", isDirectory: true)
        if let run = ProcessInfo.processInfo.arguments.firstIndex(of: "--ui-testing"),
           ProcessInfo.processInfo.arguments.indices.contains(run + 1) {
            base = base.appendingPathComponent("UITests-\(ProcessInfo.processInfo.arguments[run + 1])", isDirectory: true)
        }
        return base.appendingPathComponent("Command History", isDirectory: true)
    }

    // MARK: - Reading

    /// Every command kept for a machine, in no order.
    func records(for machine: String) -> [TerminalCommandRecord] {
        Array(table(for: machine).values)
    }

    func count(for machine: String) -> Int { table(for: machine).count }

    /// The command recorded last on a machine this run.
    func lastCommand(on machine: String) -> String? { lastRecorded[machine] }

    // MARK: - Recording

    /// Whether a command may be kept: not blank, not marked private with a space first, not a secret.
    nonisolated static func keeps(_ command: String) -> Bool {
        guard let first = command.first, first != " ", first != "\t" else { return false }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2_000 else { return false }
        return !TerminalCommandSecrets.mayHoldSecret(trimmed)
    }

    /// A command run on `machine` in `folder`. Returns whether it was kept.
    @discardableResult
    func record(_ command: String, machine: String, folder: String?, at date: Date = Date()) -> Bool {
        guard Self.keeps(command) else {
            lastRecorded[machine] = nil
            return false
        }
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var table = table(for: machine)
        var record = table[command] ?? TerminalCommandRecord(command: command, count: 0, lastUsed: date)
        record.count += 1
        record.lastUsed = date
        record.imported = false
        if let folder, !folder.isEmpty { Self.bump(&record.folders, folder) }
        if let previous = lastRecorded[machine], previous != command { Self.bump(&record.after, previous) }
        table[command] = record
        loaded[machine] = Self.trimmed(table)
        lastRecorded[machine] = command
        scheduleSave(machine)
        return true
    }

    /// The exit status of the command recorded last on `machine`.
    func finish(machine: String, status: Int?) {
        guard let status, let last = lastRecorded[machine], var record = table(for: machine)[last] else { return }
        record.lastStatus = status
        loaded[machine]?[last] = record
        scheduleSave(machine)
    }

    /// Commands read from the machine's own history file, oldest first. Those already kept keep their counts;
    /// returns how many were new.
    @discardableResult
    func importCommands(_ entries: [ShellHistoryEntry], machine: String, now: Date = Date()) -> Int {
        var table = table(for: machine)
        var added = 0
        for (index, entry) in entries.enumerated() where Self.keeps(entry.command) {
            let command = entry.command.trimmingCharacters(in: .whitespacesAndNewlines)
            // Files without times keep their order: the newest last, a second apart.
            let date = entry.date ?? now.addingTimeInterval(TimeInterval(index - entries.count))
            if var record = table[command] {
                if record.imported {
                    record.count += 1
                    record.lastUsed = max(record.lastUsed, date)
                    table[command] = record
                }
            } else {
                table[command] = TerminalCommandRecord(command: command, lastUsed: date, imported: true)
                added += 1
            }
        }
        loaded[machine] = Self.trimmed(table)
        scheduleSave(machine)
        return added
    }

    func forget(_ command: String, machine: String) {
        guard table(for: machine)[command] != nil else { return }
        loaded[machine]?[command] = nil
        if lastRecorded[machine] == command { lastRecorded[machine] = nil }
        scheduleSave(machine)
    }

    func forgetAll(machine: String) {
        loaded[machine] = [:]
        lastRecorded[machine] = nil
        scheduleSave(machine)
    }

    /// Every machine's history, files and all.
    func forgetEverything() {
        loaded.removeAll()
        lastRecorded.removeAll()
        pendingSaves.removeAll()
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Storage

    private func table(for machine: String) -> [String: TerminalCommandRecord] {
        if let table = loaded[machine] { return table }
        var table: [String: TerminalCommandRecord] = [:]
        if let url = fileURL(for: machine), let data = try? Data(contentsOf: url) {
            do {
                for record in try JSONDecoder().decode([TerminalCommandRecord].self, from: data) {
                    table[record.command] = record
                }
            } catch {
                Self.logger.error("A machine's command history could not be read; it starts afresh: \(error.localizedDescription, privacy: .public)")
            }
        }
        loaded[machine] = table
        return table
    }

    /// The file a machine's history is kept in: its key, made safe for a file name.
    func fileURL(for machine: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let name = String(machine.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return folder?.appendingPathComponent(name + ".json")
    }

    private func scheduleSave(_ machine: String) {
        pendingSaves.insert(machine)
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.saveNow()
        }
    }

    /// Writes every machine changed since the last save. Tests call it; the app does after a moment's quiet.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        let machines = pendingSaves
        pendingSaves.removeAll()
        guard let folder else { return }
        for machine in machines {
            guard let url = fileURL(for: machine) else { continue }
            let records = Array((loaded[machine] ?? [:]).values).sorted { $0.lastUsed > $1.lastUsed }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var excluded = folder
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? excluded.setResourceValues(values)
                if records.isEmpty {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                let data = try JSONEncoder().encode(records)
                #if os(macOS)
                try data.write(to: url, options: .atomic)
                #else
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                #endif
            } catch {
                Self.logger.error("A machine's command history could not be saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Rules

    private nonisolated static func bump(_ counts: inout [String: Int], _ key: String) {
        counts[key, default: 0] += 1
        if counts.count > detailLimit, let least = counts.min(by: { $0.value < $1.value })?.key, least != key {
            counts[least] = nil
        }
    }

    /// At most `limit`: those used least, then longest ago, go first.
    nonisolated static func trimmed(_ table: [String: TerminalCommandRecord]) -> [String: TerminalCommandRecord] {
        guard table.count > limit else { return table }
        let kept = table.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.lastUsed > $1.lastUsed
        }.prefix(limit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.command, $0) })
    }
}
