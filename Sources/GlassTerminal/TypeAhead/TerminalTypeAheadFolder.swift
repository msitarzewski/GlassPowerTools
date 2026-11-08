//
//  TerminalTypeAheadFolder.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead's folder source (D102, 2026-11-06): what the shell's current folder holds, for the argument being
//  typed. Git branches and remotes, file and folder names, `package.json` scripts, Makefile and justfile targets.
//  Read on this Mac from the files, on a server over the terminal's own SFTP, once per folder and again after a
//  command runs there; never while a key waits on it. `tasks/2026-11/2026-11-06_type-ahead.md`, source 5.
//

import Foundation
import GlassSSHTransport
import NIOCore
import NIOFoundationCompat
import os

/// What an argument is, where the folder can fill it.
nonisolated enum TerminalFolderArgument: Equatable, Sendable {
    case branch, remote, file, folder, script, target
}

/// Reads a folder: this Mac's, or a server's over SFTP.
protocol TerminalFolderReader: Sendable {
    /// The folder's entries, at most `limit`; nil when it can't be read.
    func list(_ folder: String, limit: Int) async -> [TerminalFolderEntry]?
    /// A small file's contents; nil when it can't be read or is larger than `maxBytes`.
    func read(_ path: String, maxBytes: Int) async -> Data?
    /// Whether a path exists.
    func exists(_ path: String) async -> Bool
}

nonisolated struct TerminalFolderEntry: Equatable, Sendable {
    let name: String
    let isFolder: Bool
}

/// What one folder holds, as last read.
nonisolated struct TerminalFolderSnapshot: Equatable, Sendable {
    var entries: [TerminalFolderEntry] = []
    var branches: [String] = []
    var remotes: [String] = []
    var scripts: [String] = []
    var targets: [String] = []
    var read = Date()
}

@MainActor
final class TerminalTypeAheadFolder {
    private nonisolated static let logger = Logger(subsystem: "sh.glas", category: "type-ahead")
    /// A folder read longer ago than this is read again when next asked.
    nonisolated static let freshFor: TimeInterval = 30
    private let reader: any TerminalFolderReader
    /// What `~` is to the reader: this Mac's home folder, or "" on a server, whose SFTP paths start in its home.
    private let home: String
    private var snapshots: [String: TerminalFolderSnapshot] = [:]
    private var loading: Set<String> = []
    /// Other folders' entries, for a path typed into one (`cd ~/Software/gl`): only their names are read.
    private var listings: [String: (entries: [TerminalFolderEntry], read: Date)] = [:]
    private var listing: Set<String> = []
    /// After a folder has been read: the line's suggestion can be worked out again.
    var onLoaded: (() -> Void)?

    init(reader: any TerminalFolderReader, home: String = "") {
        self.reader = reader
        self.home = home
    }

    /// Words for the word being typed on `line` in `folder`, where `kind` says what it is.
    func words(line: String, folder: String?, kind: TerminalFolderArgument?) -> [(word: String, score: Double)] {
        guard let kind else { return [] }
        let word = TerminalTypeAheadEngine.currentWord(of: line).word
        // A path (2026-11-07, the owner's `cd ~/Software/gl` offered nothing): the names in the folder it names.
        if kind == .file || kind == .folder, let slash = word.lastIndex(of: "/") {
            let typedFolder = String(word[...slash])
            guard let named = Self.folder(of: typedFolder, in: folder, home: home) else { return [] }
            guard let read = listings[named] else {
                list(named)
                return []
            }
            if Date().timeIntervalSince(read.read) > Self.freshFor { list(named) }
            return Self.names(read.entries, kind: kind, typed: String(word[word.index(after: slash)...]))
                .map { (typedFolder + $0.word, $0.score) }
        }
        guard let folder else { return [] }
        guard let snapshot = snapshots[folder] else {
            load(folder)
            return []
        }
        if Date().timeIntervalSince(snapshot.read) > Self.freshFor { load(folder) }
        switch kind {
        case .branch: return snapshot.branches.map { ($0, 1.1) }
        case .remote: return snapshot.remotes.map { ($0, 1.1) }
        case .script: return snapshot.scripts.map { ($0, 1.1) }
        case .target: return snapshot.targets.map { ($0, 1.1) }
        case .folder, .file: return Self.names(snapshot.entries, kind: kind, typed: word)
        }
    }

    /// A folder's names for a word: folders only for `cd`, a folder with its slash; a hidden one only once its dot is
    /// typed, as zsh and bash complete them (and so `cd ` doesn't offer `.git/` first).
    nonisolated static func names(_ entries: [TerminalFolderEntry], kind: TerminalFolderArgument,
                                  typed: String) -> [(word: String, score: Double)] {
        entries.compactMap { entry in
            guard kind == .file || entry.isFolder, !entry.name.hasPrefix(".") || typed.hasPrefix(".") else { return nil }
            return (shellWord(entry.name) + (entry.isFolder ? "/" : ""), kind == .file && entry.isFolder ? 0.8 : 0.9)
        }
    }

    /// The folder a typed path's folder part names (`~/Software/`, `/usr/`, `src/`), as `reader` reads it: `~` is
    /// `home` (dropped where that is "", a server's SFTP paths starting in its home), and a relative one is in `folder`.
    /// Nil for one it can't say: `~ann/`, quotes, or relative with no current folder.
    nonisolated static func folder(of typedFolder: String, in folder: String?, home: String) -> String? {
        guard !typedFolder.contains(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        // The shell's escapes off: `My\ Notes/` is "My Notes/".
        var path = ""
        var escaped = false
        for character in typedFolder {
            if escaped || character != "\\" { path.append(character); escaped = false } else { escaped = true }
        }
        if path.hasPrefix("~/") {
            let rest = String(path.dropFirst(2))
            return home.isEmpty ? (rest.isEmpty ? "." : rest) : (home as NSString).appendingPathComponent(rest) + "/"
        }
        if path.hasPrefix("~") { return nil }
        if path.hasPrefix("/") { return path }
        guard let folder else { return nil }
        return (folder as NSString).appendingPathComponent(path) + "/"
    }

    private func list(_ folder: String) {
        guard !listing.contains(folder) else { return }
        listing.insert(folder)
        let reader = reader
        Task { [weak self] in
            let entries = (await reader.list(folder, limit: 500) ?? [])
                .filter { $0.name != "." && $0.name != ".." }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard let self else { return }
            self.listing.remove(folder)
            self.listings[folder] = (entries, Date())
            if self.listings.count > 48, let oldest = self.listings.min(by: { $0.value.read < $1.value.read })?.key {
                self.listings[oldest] = nil
            }
            self.onLoaded?()
        }
    }

    /// Something ran in `folder`: what it holds may have changed.
    func invalidate(_ folder: String?) {
        // A command may have changed any folder a path names (`mkdir -p ~/x/y`).
        for named in listings.keys { listings[named]?.read = .distantPast }
        guard let folder else { return }
        snapshots[folder]?.read = .distantPast
    }

    func snapshot(for folder: String) -> TerminalFolderSnapshot? { snapshots[folder] }

    private func load(_ folder: String) {
        guard !loading.contains(folder) else { return }
        loading.insert(folder)
        let reader = reader
        Task { [weak self] in
            let snapshot = await Self.read(folder, with: reader)
            guard let self else { return }
            self.loading.remove(folder)
            self.snapshots[folder] = snapshot
            if self.snapshots.count > 24, let oldest = self.snapshots.min(by: { $0.value.read < $1.value.read })?.key {
                self.snapshots[oldest] = nil
            }
            self.onLoaded?()
        }
    }

    /// Everything the source offers for one folder, read off the main actor.
    nonisolated static func read(_ folder: String, with reader: any TerminalFolderReader) async -> TerminalFolderSnapshot {
        var snapshot = TerminalFolderSnapshot()
        let entries = await reader.list(folder, limit: 500) ?? []
        snapshot.entries = entries.filter { $0.name != "." && $0.name != ".." }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let names = Set(entries.map(\.name))
        if names.contains("package.json"), let data = await reader.read(join(folder, "package.json"), maxBytes: 512 * 1024) {
            snapshot.scripts = packageScripts(data)
        }
        for makefile in ["Makefile", "makefile", "GNUmakefile"] where names.contains(makefile) {
            if let data = await reader.read(join(folder, makefile), maxBytes: 512 * 1024) {
                snapshot.targets += makeTargets(String(decoding: data, as: UTF8.self))
            }
        }
        for justfile in ["justfile", "Justfile", ".justfile"] where names.contains(justfile) {
            if let data = await reader.read(join(folder, justfile), maxBytes: 256 * 1024) {
                snapshot.targets += justRecipes(String(decoding: data, as: UTF8.self))
            }
        }
        if let git = await gitFolder(from: folder, with: reader) {
            snapshot.branches = await branches(in: git, with: reader)
            if let config = await reader.read(join(git, "config"), maxBytes: 128 * 1024) {
                snapshot.remotes = gitRemotes(String(decoding: config, as: UTF8.self))
            }
        }
        snapshot.read = Date()
        return snapshot
    }

    // MARK: - Parsing (pure, tested)

    /// `package.json`'s script names, in the file's order.
    nonisolated static func packageScripts(_ data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = object["scripts"] as? [String: Any] else { return [] }
        // JSONSerialization loses the order; the file's own order reads better, so find the keys in the text.
        let text = String(decoding: data, as: UTF8.self)
        return scripts.keys.sorted {
            (text.range(of: "\"\($0)\"")?.lowerBound ?? text.endIndex) < (text.range(of: "\"\($1)\"")?.lowerBound ?? text.endIndex)
        }
    }

    /// A Makefile's targets: `name:` at a line's start, not a variable (`:=`), a pattern (`%`), or a special
    /// target (`.PHONY`).
    nonisolated static func makeTargets(_ text: String) -> [String] {
        var targets: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = line.first, first != "\t", first != " ", first != "#", first != "." else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let after = line[line.index(after: colon)...]
            if after.hasPrefix("=") || line[..<colon].contains("=") { continue }
            for name in line[..<colon].split(separator: " ") where !name.contains("%") && !name.contains("$") {
                let target = String(name)
                if !targets.contains(target) { targets.append(target) }
            }
        }
        return targets
    }

    /// A justfile's recipes: `name args…:` at a line's start, not an assignment (`:=`), not a private one (`_name`).
    nonisolated static func justRecipes(_ text: String) -> [String] {
        var recipes: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let first = line.first, first.isLetter || first.isNumber || first == "@" else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[line.index(after: colon)...].hasPrefix("=") { continue }
            let head = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard let name = head.split(separator: " ").first.map({ String($0.drop(while: { $0 == "@" })) }),
                  !name.isEmpty, !name.contains("="), !name.hasPrefix("_"),
                  !["set", "alias", "export", "import", "mod"].contains(name) else { continue }
            if !recipes.contains(name) { recipes.append(name) }
        }
        return recipes
    }

    /// `[remote "name"]` sections of a git config.
    nonisolated static func gitRemotes(_ config: String) -> [String] {
        config.split(separator: "\n").compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[remote \""), line.hasSuffix("\"]") else { return nil }
            return String(line.dropFirst(9).dropLast(2))
        }
    }

    /// Branch names from `packed-refs`: local ones, then remote ones as `remote/branch`.
    nonisolated static func packedBranches(_ text: String) -> (local: [String], remote: [String]) {
        var local: [String] = [], remote: [String] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            let ref = parts[1]
            if ref.hasPrefix("refs/heads/") { local.append(String(ref.dropFirst(11))) }
            if ref.hasPrefix("refs/remotes/"), !ref.hasSuffix("/HEAD") { remote.append(String(ref.dropFirst(13))) }
        }
        return (local, remote)
    }

    /// A name as the shell takes it: spaces and the shell's own characters escaped.
    nonisolated static func shellWord(_ name: String) -> String {
        var word = ""
        for character in name {
            if " \t\"'\\$`!&;|<>()*?[]{}#~".contains(character) { word.append("\\") }
            word.append(character)
        }
        return word
    }

    // MARK: - Git

    /// The repository's `.git` folder: in `folder` or up to eight folders above it.
    private nonisolated static func gitFolder(from folder: String, with reader: any TerminalFolderReader) async -> String? {
        var current = folder
        for _ in 0..<8 {
            let candidate = join(current, ".git")
            if await reader.exists(join(candidate, "HEAD")) { return candidate }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current, !parent.isEmpty else { return nil }
            current = parent
        }
        return nil
    }

    private nonisolated static func branches(in git: String, with reader: any TerminalFolderReader) async -> [String] {
        var local: [String] = []
        var remote: [String] = []
        // Loose refs, a few folders deep (`feature/login`).
        var pending: [(path: String, prefix: String)] = [(join(git, "refs/heads"), "")]
        var visited = 0
        while let next = pending.popLast(), visited < 40 {
            visited += 1
            for entry in await reader.list(next.path, limit: 400) ?? [] where entry.name != "." && entry.name != ".." {
                let name = next.prefix + entry.name
                if entry.isFolder { pending.append((join(next.path, entry.name), name + "/")) } else { local.append(name) }
            }
        }
        if let packed = await reader.read(join(git, "packed-refs"), maxBytes: 2 * 1024 * 1024) {
            let found = packedBranches(String(decoding: packed, as: UTF8.self))
            local += found.local
            remote += found.remote
        }
        var seen: Set<String> = []
        return (local.sorted() + remote.sorted()).filter { seen.insert($0).inserted }
    }

    private nonisolated static func join(_ folder: String, _ name: String) -> String {
        folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }
}

// MARK: - Readers

/// This Mac's files.
nonisolated struct TerminalLocalFolderReader: TerminalFolderReader {
    func list(_ folder: String, limit: Int) async -> [TerminalFolderEntry]? {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        return items.prefix(limit).map {
            TerminalFolderEntry(name: $0.lastPathComponent,
                                isFolder: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }
    }

    func read(_ path: String, maxBytes: Int) async -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    func exists(_ path: String) async -> Bool { FileManager.default.fileExists(atPath: path) }
}

/// One SFTP client for a terminal's folder reads, opened when first needed and again after one fails (the
/// connection dropped and came back).
actor TerminalSFTPClientHolder {
    private let open: @Sendable () async throws -> SFTPClient
    private var client: SFTPClient?

    init(open: @escaping @Sendable () async throws -> SFTPClient) {
        self.open = open
    }

    func get() async throws -> SFTPClient {
        if let client { return client }
        let opened = try await open()
        client = opened
        return opened
    }

    func reset() {
        let old = client
        client = nil
        Task { try? await old?.close() }
    }

    /// After a failed read: a missing file is an answer, a closed session isn't, so only that one is reopened.
    func resetIfInactive() async {
        guard let client else { return }
        if await !client.isActive { reset() }
    }
}

/// A server's files, over its terminal's own connection (`TerminalRemoteDrops.openClient`).
nonisolated struct TerminalRemoteFolderReader: TerminalFolderReader {
    let holder: TerminalSFTPClientHolder

    func list(_ folder: String, limit: Int) async -> [TerminalFolderEntry]? {
        do {
            let names = try await holder.get().listDirectory(atPath: folder)
            return names.flatMap(\.components).prefix(limit).map {
                TerminalFolderEntry(name: $0.filename,
                                    isFolder: ($0.attributes.permissions ?? 0) & 0o170000 == 0o040000)
            }
        } catch {
            await resetIfDisconnected(error)
            return nil
        }
    }

    func read(_ path: String, maxBytes: Int) async -> Data? {
        do {
            let client = try await holder.get()
            guard let size = try await client.getAttributes(at: path).size, size <= UInt64(maxBytes) else { return nil }
            let file = try await client.openFile(filePath: path, flags: .read)
            let buffer = try? await file.readAll()
            try? await file.close()
            return buffer.map { Data(buffer: $0) }
        } catch {
            await resetIfDisconnected(error)
            return nil
        }
    }

    func exists(_ path: String) async -> Bool {
        do {
            _ = try await holder.get().getAttributes(at: path)
            return true
        } catch {
            await resetIfDisconnected(error)
            return false
        }
    }

    private func resetIfDisconnected(_ error: Error) async {
        await holder.resetIfInactive()
    }
}
