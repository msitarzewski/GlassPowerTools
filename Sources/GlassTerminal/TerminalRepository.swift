//
//  TerminalRepository.swift
//  Glass Power Tools — GlassTerminal
//
//  W11 (2026-10-09): the repository and branch a terminal is working in, for its name. The owner
//  runs many agents in tmux tabs, and a tab said "✳ Claude Code" over a long folder path: "it would
//  be super helpful to have the repo in there, and branch."
//
//  On this Mac the files are read and `git` is never run: walking up from the folder to a `.git`
//  folder, or a `gitdir:` file (a worktree, a submodule), then its HEAD. A host is asked with one
//  small `git` command over the exec channel. A host without git, or a folder outside a repository,
//  answers nothing, and the tab reads as it did before.
//

import Foundation

/// The repository a terminal's folder is in.
nonisolated struct TerminalRepository: Equatable, Hashable, Sendable {
    /// The repository's name: its top folder's, or for a worktree the main repository's, so a
    /// worktree of `app` is still `app`.
    var name: String
    /// The branch checked out, or for a detached HEAD its commit, seven characters. Nil when not known.
    var branch: String?
    /// The top folder of the working tree, when known: a folder inside it is said relative to it.
    var root: String?

    /// The most folders a walk looks at: deeper than any real folder, and a bound on a bad path.
    static let maximumDepth = 64
}

/// What looking up a folder's repository came to.
nonisolated enum TerminalRepositoryAnswer: Equatable, Sendable {
    case repository(TerminalRepository)
    /// The folder is in no repository, or the host cannot say: it has no git.
    case none
    /// Nothing answered — the folder is not known, or the host did not reply. What was known
    /// stands, and the next lookup asks again.
    case unknown

    var repository: TerminalRepository? {
        if case .repository(let repository) = self { repository } else { nil }
    }
}

// MARK: Reading the files (this Mac)

nonisolated extension TerminalRepository {
    /// The name a repository is called by: for a worktree, the repository its common folder
    /// belongs to (`app/.git`, or a bare `app.git`); otherwise its top folder's.
    static func name(top: String, commonDirectory: String?) -> String {
        if let common = commonDirectory.map(standardized) {
            let last = lastComponent(common)
            if last == ".git" {
                let owner = lastComponent(parent(of: common))
                if !owner.isEmpty { return owner }
            } else if last.hasSuffix(".git"), last.count > 4 {
                return String(last.dropLast(4))
            }
        }
        return lastComponent(top)
    }

    /// The branch HEAD names: `ref: refs/heads/feature/x` is `feature/x`; a detached HEAD's commit
    /// is its first seven characters. Nil for anything else.
    static func branch(fromHead head: String) -> String? {
        let head = head.trimmingCharacters(in: .whitespaces)
        if head.hasPrefix("ref:") {
            var reference = head.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if reference.hasPrefix("refs/heads/") {
                reference = String(reference.dropFirst("refs/heads/".count))
            } else if reference.hasPrefix("refs/") {
                reference = String(reference.dropFirst("refs/".count))
            }
            // A repository keeping its references in a reftable points HEAD at this placeholder.
            guard reference != ".invalid" else { return nil }
            return TerminalSessionNaming.displayText(reference)
        }
        guard head.count >= 40, head.allSatisfy(\.isHexDigit) else { return nil }
        return String(head.prefix(7)).lowercased()
    }

    /// An absolute path with `.`, `..` and repeated slashes taken out — by its text alone, since
    /// looking at the disk is what a walk must keep to a minimum.
    static func standardized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    static func parent(of path: String) -> String {
        standardized(path + "/..")
    }

    static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    /// `path` as written in a git file: relative to the folder holding that file.
    static func resolved(_ path: String, from folder: String) -> String {
        standardized(path.hasPrefix("/") ? path : folder + "/" + path)
    }
}

#if os(macOS)
nonisolated extension TerminalRepository {
    /// A mounted volume, as the system last knew it.
    struct Volume: Equatable, Sendable {
        var path: String
        var isLocal: Bool
    }

    /// The repository `folder` is in, from the files alone, or nil. The walk stops below the home
    /// folder — a dotfiles repository there would claim every folder in it — and at the root of
    /// the folder's volume, and never starts on a volume that is not local: a network volume
    /// that stops answering can keep a read waiting as long as it does not answer.
    /// - Parameter volumes: the mounted volumes; tests give their own.
    static func read(folder: String, home: String?, volumes: [Volume]? = nil) -> TerminalRepository? {
        guard folder.hasPrefix("/") else { return nil }
        var current = standardized(folder)
        let home = home.flatMap { $0.hasPrefix("/") ? standardized($0) : nil }
        let volume = volume(of: current, in: volumes ?? mountedVolumes())
        if volume?.isLocal == false { return nil }
        for _ in 0..<maximumDepth {
            if current == "/" || current == home { return nil }
            if let repository = repository(at: current) { return repository }
            if current == volume?.path { return nil }
            current = parent(of: current)
        }
        return nil
    }

    /// The read, off the main actor: it looks at files.
    @concurrent
    static func readOffMain(folder: String, home: String?) async -> TerminalRepositoryAnswer {
        read(folder: folder, home: home).map(TerminalRepositoryAnswer.repository) ?? .none
    }

    /// `top` holds a `.git` folder, or a `gitdir:` file pointing at one, whose HEAD reads.
    private static func repository(at top: String) -> TerminalRepository? {
        let dotGit = top + "/.git"
        var info = stat()
        guard stat(dotGit, &info) == 0 else { return nil }
        let gitDirectory: String
        var commonDirectory: String?
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            gitDirectory = dotGit
        case S_IFREG:
            // A worktree's or a submodule's: `gitdir: <path>`, relative to the folder it is in.
            guard let line = firstLine(of: dotGit), line.hasPrefix("gitdir:") else { return nil }
            let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return nil }
            gitDirectory = resolved(target, from: top)
            // A worktree names the repository it belongs to; a submodule has no common folder.
            commonDirectory = firstLine(of: gitDirectory + "/commondir").map { resolved($0, from: gitDirectory) }
        default:
            return nil
        }
        // Without a HEAD it is not a repository, as git sees it; the walk goes on upward.
        guard let head = firstLine(of: gitDirectory + "/HEAD"),
              let name = TerminalSessionNaming.displayText(name(top: top, commonDirectory: commonDirectory)) else { return nil }
        return TerminalRepository(name: name, branch: branch(fromHead: head), root: top)
    }

    /// The first line of a small, ordinary file. Anything else is not read: a pipe named HEAD
    /// would wait forever to be read.
    private static func firstLine(of path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 4_096,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4_096),
              let line = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first
        else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The volumes as the system last knew them. `MNT_NOWAIT` asks no volume anything, so one that
    /// has stopped answering cannot hold this up.
    static func mountedVolumes() -> [Volume] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        // Room for a few mounted in between.
        var entries = Array(repeating: statfs(), count: Int(count) + 4)
        let filled = entries.withUnsafeMutableBufferPointer { buffer in
            getfsstat(buffer.baseAddress, Int32(buffer.count * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        guard filled > 0 else { return [] }
        return entries.prefix(Int(filled)).map { entry in
            var name = entry.f_mntonname
            let path = withUnsafeBytes(of: &name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return Volume(path: path, isLocal: entry.f_flags & UInt32(MNT_LOCAL) != 0)
        }
    }

    /// The volume a path is on: the mount point that is the longest start of it.
    static func volume(of path: String, in volumes: [Volume]) -> Volume? {
        volumes.filter { $0.path == "/" || path == $0.path || path.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }
}
#endif

// MARK: Asking a host (SSH)

nonisolated extension TerminalRepository {
    /// Starts the answer, so a login script's chatter before it is not read as one.
    static let remoteMarker = "__glass_repo__"

    /// Asks a host which repository `folder` is in: after the marker, the top folder, git's
    /// common folder (relative in a main working tree, absolute in a worktree), the branch or
    /// the detached commit, and the home folder as the system names it. Nothing without git, or
    /// for a folder that is gone or in no repository. A Mac without its developer tools has a
    /// `git` that offers to install them, so there it is not run at all.
    static func remoteCommand(folder: String) -> String {
        "sh -c \(TerminalTmux.quoted(TerminalTmux.searchPath + remoteScript)) _ \(TerminalTmux.quoted(folder))"
    }

    /// The folder is the script's `$1`, never part of its text. Anything but a full path is no
    /// folder: `cd ""` would stay in the home folder and answer for it.
    static let remoteScript = "case $1 in /*) ;; *) exit 0;; esac; "
        + "command -v git >/dev/null 2>&1 || exit 0; "
        + "if [ -x /usr/bin/xcode-select ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then exit 0; fi; "
        + #"cd -- "$1" 2>/dev/null || exit 0; "#
        + "t=$(git rev-parse --show-toplevel --git-common-dir 2>/dev/null) || exit 0; "
        + "b=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short=7 HEAD 2>/dev/null); "
        + #"h=$(cd -- "$HOME" 2>/dev/null && pwd -P); "#
        + "printf '\(remoteMarker)\\n%s\\n%s\\n%s\\n' \"$t\" \"$b\" \"$h\""

    /// Reads a host's answer. A repository at the home folder or above it is no answer, as on
    /// this Mac: it holds dotfiles, and would claim every folder.
    static func parseRemote(_ output: String) -> TerminalRepositoryAnswer {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard let marker = lines.lastIndex(of: remoteMarker) else { return .none }
        let answer = Array(lines[(marker + 1)...])
        guard answer.count >= 2, answer[0].hasPrefix("/") else { return .none }
        let top = standardized(answer[0])
        if answer.count > 3, answer[3].hasPrefix("/") {
            let home = standardized(answer[3])
            if top == "/" || home == top || home.hasPrefix(top + "/") { return .none }
        }
        // Relative only in a main working tree, whose name is its top folder's.
        let common = answer[1].hasPrefix("/") ? answer[1] : nil
        guard let name = TerminalSessionNaming.displayText(name(top: top, commonDirectory: common)) else { return .none }
        let branch = answer.count > 2 ? TerminalSessionNaming.displayText(answer[2]) : nil
        return .repository(TerminalRepository(name: name, branch: branch, root: top))
    }

    /// The folder a shell reported (OSC 7) as a path: shells send `file://host/path`, encoded.
    static func path(fromReported reported: String?) -> String? {
        guard let reported, !reported.isEmpty else { return nil }
        if reported.hasPrefix("/") { return reported }
        guard let url = URL(string: reported), url.isFileURL, url.path.hasPrefix("/") else { return nil }
        return url.path
    }
}

// MARK: The cache

/// Repositories by folder, shared by every tab standing in one, and read again when asked after
/// `maximumAge`: a checkout changes the branch (W11). One read of a folder at a time.
final class TerminalRepositoryCache {
    static let shared = TerminalRepositoryCache()

    struct Key: Hashable, Sendable {
        /// The host the folder is on; nil for this Mac.
        var host: UUID?
        var folder: String
    }

    /// The most folders remembered: far more than tabs open at once.
    static let capacity = 256

    private struct Entry {
        var answer: TerminalRepositoryAnswer
        var readAt: ContinuousClock.Instant
    }

    private var entries: [Key: Entry] = [:]
    private var reads: [Key: Task<TerminalRepositoryAnswer, Never>] = [:]
    private let now: () -> ContinuousClock.Instant

    /// - Parameter now: the clock; tests move their own.
    init(now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    /// The folder's answer, read again when the last read is `maximumAge` old. An unanswered
    /// read is not remembered, so the next ask tries again.
    func answer(for key: Key, maximumAge: Duration,
                read: @escaping @Sendable @MainActor () async -> TerminalRepositoryAnswer) async -> TerminalRepositoryAnswer {
        if let entry = entries[key], now() - entry.readAt < maximumAge { return entry.answer }
        if let reading = reads[key] { return await reading.value }
        let reading = Task { await read() }
        reads[key] = reading
        let answer = await reading.value
        reads[key] = nil
        guard answer != .unknown else { return answer }
        if entries[key] == nil, entries.count >= Self.capacity,
           let oldest = entries.min(by: { $0.value.readAt < $1.value.readAt })?.key {
            entries[oldest] = nil
        }
        entries[key] = Entry(answer: answer, readAt: now())
        return answer
    }
}
