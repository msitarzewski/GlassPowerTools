//
//  GlassEditorGitRefs.swift
//  Glass Power Tools — GlassEditor
//
//  What git says about a repository beyond its working tree, read (2026-10-28, "build git now, end
//  to end, first class"): its branches, tags, stashes and remotes, its commits and the lines of
//  their graph, and who last changed each line of a file. Each is read from a format asked for
//  with NUL between fields, so a name or a message can hold anything else.
//

import Foundation

/// A branch, here or on a remote.
public struct GlassEditorGitBranch: Equatable, Sendable, Identifiable, Hashable {
    /// `main`, or `origin/main`.
    public var name: String
    public var isRemote: Bool
    /// The remote's name for a remote branch.
    public var remote: String?
    public var commit: String
    /// The branch it follows, as `origin/main`.
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    /// Its upstream is gone from the remote.
    public var upstreamGone = false
    public var date: Date?
    /// Its commit's first line.
    public var subject: String
    public var isCurrent = false

    public var id: String { (isRemote ? "remotes/" : "heads/") + name }
    /// A remote branch's name without its remote: `main` for `origin/main`.
    public var shortName: String {
        guard isRemote, let remote, name.hasPrefix(remote + "/") else { return name }
        return String(name.dropFirst(remote.count + 1))
    }

    /// Each line of `GlassEditorGitCommand.branches`; a remote's `HEAD` pointer is left out.
    public static func parse(_ data: Data) -> [GlassEditorGitBranch] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7 else { return nil }
            let ref = fields[0]
            var branch: GlassEditorGitBranch
            if ref.hasPrefix("refs/heads/") {
                branch = GlassEditorGitBranch(name: String(ref.dropFirst("refs/heads/".count)), isRemote: false,
                                              commit: fields[1], subject: fields[5])
            } else if ref.hasPrefix("refs/remotes/") {
                let name = String(ref.dropFirst("refs/remotes/".count))
                guard !name.hasSuffix("/HEAD") else { return nil }
                branch = GlassEditorGitBranch(name: name, isRemote: true,
                                              remote: name.split(separator: "/", maxSplits: 1).first.map(String.init),
                                              commit: fields[1], subject: fields[5])
            } else {
                return nil
            }
            branch.upstream = fields[2].isEmpty ? nil : fields[2]
            // "ahead 2, behind 1", "gone", or nothing.
            for part in fields[3].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if part.hasPrefix("ahead ") { branch.ahead = Int(part.dropFirst(6)) ?? 0 }
                if part.hasPrefix("behind ") { branch.behind = Int(part.dropFirst(7)) ?? 0 }
                if part == "gone" { branch.upstreamGone = true }
            }
            branch.date = TimeInterval(fields[4]).map(Date.init(timeIntervalSince1970:))
            branch.isCurrent = fields[6] == "*"
            return branch
        }
    }
}

public struct GlassEditorGitTag: Equatable, Sendable, Identifiable, Hashable {
    public var name: String
    /// The commit it marks.
    public var commit: String
    /// Annotated: a tag object of its own, with a message.
    public var isAnnotated: Bool
    public var date: Date?
    public var subject: String

    public var id: String { name }

    /// Each line of `GlassEditorGitCommand.tags`. An annotated tag's `objectname` is the tag object
    /// and `*objectname` the commit; a light one has only the first.
    public static func parse(_ data: Data) -> [GlassEditorGitTag] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 else { return nil }
            let annotated = !fields[2].isEmpty
            return GlassEditorGitTag(name: fields[0], commit: annotated ? fields[2] : fields[1], isAnnotated: annotated,
                                     date: TimeInterval(fields[3]).map(Date.init(timeIntervalSince1970:)), subject: fields[4])
        }
    }
}

public struct GlassEditorGitStash: Equatable, Sendable, Identifiable, Hashable {
    /// `stash@{0}`.
    public var name: String
    public var commit: String
    public var date: Date?
    /// "On main: message", or "WIP on main: abc123 subject".
    public var message: String

    public var id: String { commit }
    /// Its place in the list: 0 for the newest.
    public var index: Int { Int(name.drop(while: { $0 != "{" }).dropFirst().prefix(while: \.isNumber)) ?? 0 }

    public static func parse(_ data: Data) -> [GlassEditorGitStash] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4 else { return nil }
            return GlassEditorGitStash(name: fields[0], commit: fields[1],
                                       date: TimeInterval(fields[2]).map(Date.init(timeIntervalSince1970:)), message: fields[3])
        }
    }
}

/// A remote and where it is.
public struct GlassEditorGitRemote: Equatable, Sendable, Identifiable, Hashable {
    public var name: String
    public var address: String
    public var id: String { name }

    /// `git remote -v`: each remote's fetch address (its push address is usually the same).
    public static func parse(_ data: Data) -> [GlassEditorGitRemote] {
        var remotes: [GlassEditorGitRemote] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 2, !remotes.contains(where: { $0.name == parts[0] }) else { continue }
            remotes.append(GlassEditorGitRemote(name: parts[0], address: parts[1]))
        }
        return remotes
    }

    /// The remote's web page, for a host that has one (GitHub, GitLab, Bitbucket, and any server
    /// addressed the same way): `https://github.com/owner/repo` from an SSH or HTTPS address.
    public var webAddress: URL? {
        var text = address
        if text.hasSuffix(".git") { text.removeLast(4) }
        if text.hasPrefix("git@"), let colon = text.firstIndex(of: ":") {
            // git@github.com:owner/repo
            let host = text[text.index(text.startIndex, offsetBy: 4)..<colon]
            return URL(string: "https://\(host)/\(text[text.index(after: colon)...])")
        }
        guard var components = URLComponents(string: text), let scheme = components.scheme,
              ["https", "http", "ssh", "git"].contains(scheme), components.host != nil else { return nil }
        components.scheme = "https"
        components.user = nil
        components.password = nil
        components.port = nil
        return components.url
    }

    /// Whether the web page is GitHub's, whose addresses for a commit, a file and a comparison
    /// are known; GitLab's are the same apart from a `-/` before them.
    public var isGitHub: Bool { webAddress?.host?.lowercased() == "github.com" }
    public var isGitLab: Bool { webAddress?.host?.lowercased().contains("gitlab") == true }

    /// A commit's page.
    public func webAddress(ofCommit commit: String) -> URL? {
        webAddress?.appending(path: (isGitLab ? "-/" : "") + "commit/" + commit)
    }

    /// A file's page at `ref`, at a line when one is given.
    public func webAddress(ofFile path: String, at ref: String, line: Int? = nil) -> URL? {
        guard let page = webAddress?.appending(path: (isGitLab ? "-/" : "") + "blob/" + ref + "/" + path) else { return nil }
        guard let line else { return page }
        return URL(string: page.absoluteString + "#L\(line)")
    }

    /// A branch's page.
    public func webAddress(ofBranch branch: String) -> URL? {
        webAddress?.appending(path: (isGitLab ? "-/" : "") + "tree/" + branch)
    }

    /// Where a pull request for `branch` is begun: GitHub's comparison, GitLab's new merge request.
    public func pullRequestAddress(for branch: String) -> URL? {
        if isGitLab {
            return webAddress.flatMap { URL(string: $0.absoluteString + "/-/merge_requests/new?merge_request%5Bsource_branch%5D=\(branch)") }
        }
        return webAddress.flatMap { URL(string: $0.absoluteString + "/compare/\(branch)?expand=1") }
    }
}

// MARK: - History

public struct GlassEditorGitCommit: Equatable, Sendable, Identifiable, Hashable {
    public var hash: String
    public var parents: [String]
    public var author: String
    public var email: String
    public var date: Date
    /// What points at it: `HEAD -> main`, `origin/main`, `tag: v1`.
    public var refs: [String]
    public var subject: String
    public var body: String

    public var id: String { hash }
    public var shortHash: String { String(hash.prefix(7)) }
    public var isMerge: Bool { parents.count > 1 }
    /// The whole message.
    public var message: String { body.isEmpty ? subject : subject + "\n\n" + body }

    /// `GlassEditorGitCommand.log`'s output: records ended by U+001E, fields split by NUL.
    public static func parse(_ data: Data) -> [GlassEditorGitCommit] {
        String(decoding: data, as: UTF8.self).split(separator: "\u{1E}").compactMap { record in
            let trimmed = record.drop(while: \.isNewline)
            let fields = trimmed.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8, !fields[0].isEmpty else { return nil }
            return GlassEditorGitCommit(
                hash: fields[0], parents: fields[1].split(separator: " ").map(String.init),
                author: fields[2], email: fields[3],
                date: Date(timeIntervalSince1970: TimeInterval(fields[4]) ?? 0),
                refs: fields[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                subject: fields[6], body: fields[7].trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// The lines of the history's graph beside each commit, as `git log --graph` draws them: each
/// commit in a lane, lanes that pass it, and where its parents' lanes go.
public struct GlassEditorGitGraphRow: Equatable, Sendable {
    /// The commit's lane.
    public var lane: Int
    /// Lanes running through this row, top to bottom, besides the commit's own.
    public var passing: [Int]
    /// Lanes that come in from above into the commit (its children), the commit's own included.
    public var incoming: [Int]
    /// Lanes its parents continue in below, from the commit.
    public var outgoing: [Int]
    /// How many lanes the row is wide.
    public var width: Int

    /// The rows for commits in order, newest first, the order `--date-order` gives: a parent is
    /// always below its children.
    public static func rows(for commits: [GlassEditorGitCommit]) -> [GlassEditorGitGraphRow] {
        // Each lane holds the commit it is waiting for, or nothing.
        var lanes: [String?] = []
        var rows: [GlassEditorGitGraphRow] = []
        for commit in commits {
            let waiting = lanes.indices.filter { lanes[$0] == commit.hash }
            let lane: Int
            if let first = waiting.first {
                lane = first
            } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                lane = free
            } else {
                lane = lanes.count
                lanes.append(nil)
            }
            let incoming = waiting.isEmpty ? [] : waiting
            // The other lanes that were waiting for this commit end here.
            for other in waiting where other != lane { lanes[other] = nil }
            let passing = lanes.indices.filter { $0 != lane && lanes[$0] != nil }
            // Its first parent continues in its lane; each other parent takes a lane already waiting
            // for it, or a free one.
            var outgoing: [Int] = []
            if let first = commit.parents.first {
                lanes[lane] = first
                outgoing.append(lane)
                for parent in commit.parents.dropFirst() {
                    if let existing = lanes.firstIndex(where: { $0 == parent }) {
                        outgoing.append(existing)
                    } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                        lanes[free] = parent
                        outgoing.append(free)
                    } else {
                        lanes.append(parent)
                        outgoing.append(lanes.count - 1)
                    }
                }
            } else {
                lanes[lane] = nil
            }
            while let last = lanes.last, last == nil { lanes.removeLast() }
            let width = max([lane, passing.max() ?? 0, outgoing.max() ?? 0, incoming.max() ?? 0].max()! + 1, lanes.count)
            rows.append(GlassEditorGitGraphRow(lane: lane, passing: passing, incoming: incoming, outgoing: outgoing, width: width))
        }
        return rows
    }
}

// MARK: - Blame

/// Who last changed a run of a file's lines, and in which commit.
public struct GlassEditorBlameLine: Equatable, Sendable {
    public var commit: String
    public var author: String
    public var date: Date?
    public var summary: String
    /// Its number in the file now.
    public var number: Int
    public var text: String
    /// Not committed yet: git's all-zero commit.
    public var isUncommitted: Bool { commit.allSatisfy { $0 == "0" } }
    public var shortCommit: String { String(commit.prefix(7)) }
}

public enum GlassEditorGitBlame {
    /// `git blame --porcelain`: a header for each line (`<hash> <orig> <final> [<count>]`), the
    /// commit's details the first time it appears, then the line itself after a tab.
    public static func parse(_ data: Data) -> [GlassEditorBlameLine] {
        var details: [String: (author: String, date: Date?, summary: String)] = [:]
        var lines: [GlassEditorBlameLine] = []
        var current: (commit: String, number: Int)?
        var author = "", date: Date?, summary = ""
        for raw in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("\t") {
                guard let line = current else { continue }
                if details[line.commit] == nil { details[line.commit] = (author, date, summary) }
                let known = details[line.commit]!
                lines.append(GlassEditorBlameLine(commit: line.commit, author: known.author, date: known.date,
                                                  summary: known.summary, number: line.number, text: String(raw.dropFirst())))
                current = nil
                continue
            }
            let parts = raw.split(separator: " ", maxSplits: 1)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            if key.count == 40 || key.count == 64, key.allSatisfy(\.isHexDigit) {
                let numbers = value.split(separator: " ")
                current = (String(key), numbers.count >= 2 ? Int(numbers[1]) ?? 0 : 0)
                if let known = details[String(key)] { (author, date, summary) = known } else { author = ""; date = nil; summary = "" }
            } else if key == "author" {
                author = value
            } else if key == "author-time" {
                date = TimeInterval(value).map(Date.init(timeIntervalSince1970:))
            } else if key == "summary" {
                summary = value
            }
        }
        return lines
    }
}

// MARK: - An operation under way

/// A merge, a rebase, a cherry-pick or a revert that stopped for conflicts, or to be gone on with.
public enum GlassEditorGitOperation: String, Equatable, Sendable {
    case merge, rebase, cherryPick, revert

    /// The command that goes on with it or gives it up: `merge`, `rebase`, `cherry-pick`, `revert`.
    var verb: String {
        switch self {
        case .merge: "merge"
        case .rebase: "rebase"
        case .cherryPick: "cherry-pick"
        case .revert: "revert"
        }
    }

    public var title: String {
        switch self {
        case .merge: "Merging"
        case .rebase: "Rebasing"
        case .cherryPick: "Cherry-picking"
        case .revert: "Reverting"
        }
    }

    /// The files git keeps in the repository's folder while each is under way, the first that
    /// exists naming it: a rebase's folders first, as a rebase that stopped on a merge has both.
    static let markers: [(String, GlassEditorGitOperation)] = [
        ("rebase-merge", .rebase), ("rebase-apply", .rebase), ("MERGE_HEAD", .merge),
        ("CHERRY_PICK_HEAD", .cherryPick), ("REVERT_HEAD", .revert),
    ]
}
