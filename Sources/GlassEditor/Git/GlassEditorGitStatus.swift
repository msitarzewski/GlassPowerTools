//
//  GlassEditorGitStatus.swift
//  Glass Power Tools — GlassEditor
//
//  What `git status --porcelain=v2 --branch -z` says, read: the branch and every changed file.
//
//  Version 2 because it is the format git promises to keep, with the branch's headers in it, and
//  `-z` because a file name can hold any byte but NUL — spaces, quotes and newlines included — and
//  NUL-separated fields need no unquoting. Its paths are always from the repository's root.
//

import Foundation

/// The branch, and what changed under the project's folder.
public struct GlassEditorGitStatus: Equatable, Sendable {
    /// The branch checked out; nil when HEAD is detached.
    public var branch: String?
    /// The commit HEAD is at; nil before the repository's first commit.
    public var commit: String?
    /// The branch it follows, as `origin/main`.
    public var upstream: String?
    /// Commits here and not upstream, and there and not here.
    public var ahead = 0
    public var behind = 0
    /// In the order git gave them, which is by path.
    public var changes: [GlassEditorGitChange] = []

    public init() {}

    /// What a person calls where HEAD is: the branch, or the short commit when detached.
    public var headName: String {
        if let branch { return branch }
        if let commit { return "at \(commit.prefix(7))" }
        return "No commits"
    }

    public static func parse(_ data: Data) -> GlassEditorGitStatus {
        var status = GlassEditorGitStatus()
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        var index = 0
        while index < fields.count {
            let entry = fields[index]
            index += 1
            guard let kind = entry.first, entry.count > 2 else { continue }
            switch kind {
            case "#":
                status.readHeader(entry.dropFirst(2))
            case "1":
                // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                let parts = entry.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard parts.count == 9 else { continue }
                status.changes.append(GlassEditorGitChange(code: parts[1], path: String(parts[8])))
            case "2":
                // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>, then the original path
                let parts = entry.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                let original = index < fields.count ? fields[index] : nil
                index += 1
                guard parts.count == 10 else { continue }
                status.changes.append(GlassEditorGitChange(code: parts[1], path: String(parts[9]),
                                                           originalPath: original,
                                                           copied: parts[8].hasPrefix("C")))
            case "u":
                // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
                let parts = entry.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard parts.count == 11 else { continue }
                status.changes.append(GlassEditorGitChange(path: String(parts[10]), kind: .conflicted,
                                                           isStaged: false, isUnstaged: true))
            case "?":
                status.changes.append(GlassEditorGitChange(path: String(entry.dropFirst(2)), kind: .untracked,
                                                           isStaged: false, isUnstaged: true))
            default:
                // "!" is an ignored file, which nothing here asks for.
                continue
            }
        }
        return status
    }

    private mutating func readHeader(_ header: Substring) {
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return }
        let value = String(parts[1])
        switch parts[0] {
        case "branch.oid": commit = value == "(initial)" ? nil : value
        case "branch.head": branch = value == "(detached)" ? nil : value
        case "branch.upstream": upstream = value
        case "branch.ab":
            for count in value.split(separator: " ") {
                if count.hasPrefix("+") { ahead = Int(count.dropFirst()) ?? 0 }
                if count.hasPrefix("-") { behind = Int(count.dropFirst()) ?? 0 }
            }
        default: break
        }
    }
}

/// One changed file, as it stands against the last commit.
public struct GlassEditorGitChange: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case modified, added, deleted, renamed, copied, typeChanged, untracked, conflicted
    }

    /// From the repository's root, as git says it.
    public var path: String
    /// Where a renamed or copied file came from.
    public var originalPath: String?
    public var kind: Kind
    /// Changed in the index, ready to commit.
    public var isStaged: Bool
    /// Changed in the working tree since the index.
    public var isUnstaged: Bool

    public var id: String { path }

    public init(path: String, originalPath: String? = nil, kind: Kind, isStaged: Bool, isUnstaged: Bool) {
        self.path = path
        self.originalPath = originalPath
        self.kind = kind
        self.isStaged = isStaged
        self.isUnstaged = isUnstaged
    }

    /// From an XY code: X the index against HEAD, Y the working tree against the index, `.` for
    /// unchanged. Against the last commit, a file added to the index is added however it was
    /// edited since, and a deletion on either side is a deletion.
    init(code: Substring, path: String, originalPath: String? = nil, copied: Bool = false) {
        let characters = Array(code)
        let index = characters.first ?? ".", workTree = characters.count > 1 ? characters[1] : "."
        let kind: Kind
        if originalPath != nil {
            kind = copied ? .copied : .renamed
        } else if index == "A" {
            kind = .added
        } else if index == "D" || workTree == "D" {
            kind = .deleted
        } else if index == "T" || workTree == "T" {
            kind = .typeChanged
        } else {
            kind = .modified
        }
        self.init(path: path, originalPath: originalPath, kind: kind,
                  isStaged: index != ".", isUnstaged: workTree != ".")
    }

    /// The letter the tree and the Changes tab show, as VS Code and Zed show it.
    public var letter: String {
        switch kind {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .typeChanged: "T"
        case .untracked: "U"
        case .conflicted: "!"
        }
    }

    /// The same, in words, for VoiceOver and a tooltip.
    public var description: String {
        switch kind {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .typeChanged: "Type changed"
        case .untracked: "New, not yet added to git"
        case .conflicted: "Conflict"
        }
    }
}
