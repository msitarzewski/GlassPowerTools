//
//  GlassEditorGit.swift
//  Glass Power Tools — GlassEditor
//
//  `git`, run where a project's files are (2026-10-23: "We really, really need git support and
//  diffs in the editor now").
//
//  **The real `git`, not a reading of `.git`.** What changed in a working tree is git's to say:
//  ignore rules, renames, attributes, worktrees, index versions and the racy-timestamp cases are
//  all its own, and a second implementation of them would disagree with it in exactly the cases
//  nobody tests. Zed and VS Code run the binary for the same reason. A refresh is one command.
//
//  **Run where the files are.** A project's file access knows its machine, so it also gives the
//  runner: this Mac's `git` for a folder here, a command over the project's own SSH connection for
//  a folder on a server — on every device, so an iPhone editing a server's project sees its changes
//  too. A folder on an iPhone, iPad or Vision Pro has no `git` to run, and shows no git at all
//  rather than a control that cannot work.
//

import Foundation

/// How a `git` command ended, and what it wrote to each stream.
public struct GlassEditorCommandOutput: Sendable, Equatable {
    /// Nil when the machine did not say.
    public var exitStatus: Int?
    public var standardOutput: Data
    public var standardError: Data

    public init(exitStatus: Int?, standardOutput: Data, standardError: Data = Data()) {
        self.exitStatus = exitStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    var succeeded: Bool { exitStatus == 0 }

    /// What git said went wrong: its first line of standard error that says anything, without
    /// git's own "fatal: " or "error: " in front.
    var complaint: String? {
        let text = String(decoding: standardError, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            var said = line.trimmingCharacters(in: .whitespaces)
            for label in ["fatal: ", "error: ", "warning: "] where said.hasPrefix(label) {
                said.removeFirst(label.count)
            }
            if !said.isEmpty { return said }
        }
        return nil
    }
}

/// Runs `git` on the machine a project is on.
@MainActor
public protocol GlassEditorGitRunner {
    /// Runs `git` with `arguments`, in `directory`, and answers however it ended. Throws only when
    /// git could not be run at all.
    func git(_ arguments: [String], in directory: String) async throws -> GlassEditorCommandOutput
    /// The same, given `timeLimit` seconds instead of a minute: a push, a pull or a fetch, which
    /// wait on the network.
    func git(_ arguments: [String], in directory: String, timeLimit: TimeInterval) async throws -> GlassEditorCommandOutput
}

public extension GlassEditorGitRunner {
    func git(_ arguments: [String], in directory: String, timeLimit: TimeInterval) async throws -> GlassEditorCommandOutput {
        try await git(arguments, in: directory)
    }
}

/// Why git could not be run. Worded by `explanation(on:)`, which is told the machine's name: the
/// runner that throws it does not know what the person calls the machine.
public enum GlassEditorGitError: Error, Equatable {
    /// No `git` there.
    case notInstalled
    /// It ran past the time a status or a diff should ever take.
    case tookTooLong
    /// It wrote more than the editor reads into memory.
    case tooMuchOutput

    /// What to tell the person, about `machine` (nil for this Mac).
    public func explanation(on machine: String?) -> String {
        switch self {
        case .notInstalled:
            if let machine {
                "Git isn't installed on \(machine). Install it there (for example, sudo apt install git), then refresh."
            } else {
                "Git isn't installed on this Mac. Install Xcode's Command Line Tools (run xcode-select --install in Terminal), then refresh."
            }
        case .tookTooLong:
            "Git took longer than a minute to answer. Refresh to try again."
        case .tooMuchOutput:
            "There are too many changes to show here. Commit or stash some of them, then refresh."
        }
    }
}

/// The commands the editor runs, in one place. Every setting a person's git configuration could
/// change about the output is set on the command line instead, so what comes back is what the
/// parsers read: no colour, no external diff tool, no path quoting for non-ASCII names, `a/` and
/// `b/` whatever `diff.mnemonicPrefix` or `diff.noprefix` say, paths from the repository's root
/// whatever `diff.relative` says. `--no-optional-locks`, because a status refreshing in the
/// background must not hold the index lock while the person runs `git add` in a terminal.
enum GlassEditorGitCommand {
    static let global = ["--no-optional-locks", "-c", "core.quotePath=false"]

    /// The project's folder inside its repository: "" at the root, "Sources/App/" below it.
    static let prefix = global + ["rev-parse", "--show-prefix"]

    /// Every change under the project's folder, with the branch, in the format git keeps stable.
    static let status = global + ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all", "--", "."]

    /// The working tree against `base`: everything since the last commit, staged or not.
    static func diff(against base: String) -> [String] {
        global + ["diff", "--no-color", "--no-ext-diff", "--no-relative", "--src-prefix=a/", "--dst-prefix=b/",
                  "-M", base, "--", "."]
    }

    /// The empty tree's name in this repository's hash, to diff a repository with no commit yet.
    static let emptyTree = global + ["hash-object", "-t", "tree", "/dev/null"]

    /// A file as the last commit has it, through the filters a checkout would apply, so its line
    /// endings are the ones on disk.
    static func committed(_ repositoryPath: String) -> [String] {
        global + ["cat-file", "--filters", "HEAD:" + repositoryPath]
    }

    /// A path as a pathspec that means exactly that path from the repository's root, whatever
    /// folder git runs in and whatever characters the name holds.
    static func exactly(_ repositoryPath: String) -> String { ":(top,literal)" + repositoryPath }

    /// Stages the paths as they are now, deletions included.
    static func stage(_ repositoryPaths: [String]) -> [String] {
        global + ["add", "-A", "--"] + repositoryPaths.map(exactly)
    }

    /// Every change under the project's folder, except folders that are repositories of their own:
    /// staged, those would become links to another repository.
    static func stageAll(except nested: [String]) -> [String] {
        global + ["add", "-A", "--", "."] + nested.map { ":(exclude,top,literal)" + $0 }
    }

    /// Takes the paths back out of the next commit, leaving the files as they are. `reset` rather
    /// than `restore --staged`, which needs Git 2.23 and a first commit.
    static func unstage(_ repositoryPaths: [String]) -> [String] {
        global + ["reset", "-q", "--"] + repositoryPaths.map(exactly)
    }

    static let unstageAll = global + ["reset", "-q", "--", "."]

    /// Every staged path in the repository, inside the project's folder or not.
    static let staged = global + ["diff", "--cached", "--name-only", "--no-relative", "-z"]

    /// Commits what is staged, with git's own handling of the message's whitespace.
    static func commit(message: String) -> [String] {
        global + ["commit", "--quiet", "-m", message]
    }

    // MARK: The remote (2026-10-28)

    /// How long a push, a pull or a fetch may take: the network, and the server's hooks.
    static let networkTimeLimit: TimeInterval = 600

    /// The remotes' names, one a line.
    static let remotes = global + ["remote"]

    /// What the remote has now, for how far ahead and behind the branch is.
    static let fetch = global + ["fetch", "--quiet"]

    /// The upstream's commits, taken only when the branch can simply move up to them: a merge or a
    /// rebase is a decision for a terminal. `--no-rebase` sets a configured `pull.rebase` aside,
    /// which would make it a rebase.
    static let pull = global + ["pull", "--no-rebase", "--ff-only", "--quiet"]

    static let push = global + ["push", "--quiet"]

    /// A branch the remote doesn't have yet, pushed, and followed from now on.
    static func publish(_ branch: String, to remote: String) -> [String] {
        global + ["push", "--quiet", "--set-upstream", remote, branch]
    }

    /// The files two commits differ in, from the repository's root.
    static func changed(from old: String, to new: String) -> [String] {
        global + ["diff", "--name-only", "--no-relative", "-z", old, new]
    }
}

// MARK: This Mac

#if os(macOS)
/// This Mac's `git`, run as a process. The app is not sandboxed, so it can.
public struct GlassEditorLocalGit: GlassEditorGitRunner {
    public static let shared = GlassEditorLocalGit()

    public init() {}

    /// On a dispatch queue rather than a task: waiting for a process blocks its thread, and
    /// Swift's concurrency pool has a thread per core to share with the whole app.
    public func git(_ arguments: [String], in directory: String) async throws -> GlassEditorCommandOutput {
        try await git(arguments, in: directory, timeLimit: Self.timeLimit)
    }

    public func git(_ arguments: [String], in directory: String, timeLimit: TimeInterval) async throws -> GlassEditorCommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let executable = Self.executable else {
                    continuation.resume(throwing: GlassEditorGitError.notInstalled)
                    return
                }
                continuation.resume(with: Result { try Self.run(executable, arguments, in: directory, timeLimit: timeLimit) })
            }
        }
    }

    /// Where `git` is, found once. Homebrew's first, as a shell with it on the path would find it.
    /// `/usr/bin/git` only with Xcode or its Command Line Tools installed: without them it is a
    /// stub that opens an installer dialog instead of running, and opening a folder must never do
    /// that.
    nonisolated static let executable: String? = {
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return developerToolsInstalled() ? "/usr/bin/git" : nil
    }()

    nonisolated private static func developerToolsInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        return process.terminationStatus == 0 && !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }

    /// The most either stream may hold, and how long git may take.
    nonisolated static let outputCeiling = 32 * 1024 * 1024
    nonisolated static let timeLimit: TimeInterval = 60

    /// Runs it and reads both streams at once: a diff larger than a pipe's buffer stops git until
    /// it is read, and reading one stream to its end first would wait for ever on the other.
    nonisolated static func run(_ executable: String, _ arguments: [String],
                                in directory: String, timeLimit: TimeInterval = GlassEditorLocalGit.timeLimit) throws -> GlassEditorCommandOutput {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(filePath: directory, directoryHint: .isDirectory)
        var environment = ProcessInfo.processInfo.environment
        // Never ask for a password: there is no terminal to ask in.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let standardOutput = Pipe(), standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let state = RunState()
        let timer = DispatchWorkItem { [process] in
            guard process.isRunning else { return }
            state.note(.tookTooLong)
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeLimit, execute: timer)
        let errorRead = DispatchGroup()
        errorRead.enter()
        DispatchQueue.global().async {
            state.setError(drain(standardError.fileHandleForReading, state: state, process: process))
            errorRead.leave()
        }
        let output = drain(standardOutput.fileHandleForReading, state: state, process: process)
        errorRead.wait()
        process.waitUntilExit()
        timer.cancel()
        if let failure = state.failure { throw failure }
        return GlassEditorCommandOutput(exitStatus: Int(process.terminationStatus),
                                        standardOutput: output,
                                        standardError: state.errorOutput)
    }

    /// One stream, to its end or to the ceiling; past the ceiling git is stopped.
    nonisolated private static func drain(_ handle: FileHandle, state: RunState, process: Process) -> Data {
        var data = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard data.count + chunk.count <= outputCeiling else {
                state.note(.tooMuchOutput)
                if process.isRunning { process.terminate() }
                // Keep reading, so git is not left blocked on a full pipe while it stops.
                while let rest = try? handle.read(upToCount: 64 * 1024), !rest.isEmpty {}
                break
            }
            data.append(chunk)
        }
        return data
    }

    /// What the two readers and the timer share.
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var _failure: GlassEditorGitError?
        private var _errorOutput = Data()

        var failure: GlassEditorGitError? { lock.withLock { _failure } }
        var errorOutput: Data { lock.withLock { _errorOutput } }

        func note(_ failure: GlassEditorGitError) { lock.withLock { if _failure == nil { _failure = failure } } }
        func setError(_ data: Data) { lock.withLock { _errorOutput = data } }
    }
}
#endif

// MARK: Another machine

/// `git` over a project's own SSH connection: a command line for the machine's shell.
public struct GlassEditorRemoteGit: GlassEditorGitRunner {
    /// Runs a command line on the machine, given at most a time.
    public typealias Command = @MainActor (String, Duration) async throws -> GlassEditorCommandOutput

    private let command: Command

    public init(command: @escaping Command) {
        self.command = command
    }

    public func git(_ arguments: [String], in directory: String) async throws -> GlassEditorCommandOutput {
        try await git(arguments, in: directory, timeLimit: 60)
    }

    public func git(_ arguments: [String], in directory: String, timeLimit: TimeInterval) async throws -> GlassEditorCommandOutput {
        let output = try await command(Self.commandLine(arguments, in: directory), .seconds(timeLimit))
        // The shell's "command not found".
        if output.exitStatus == 127 { throw GlassEditorGitError.notInstalled }
        return output
    }

    /// `git -C <directory> <arguments>`, each word quoted when it needs to be.
    nonisolated static func commandLine(_ arguments: [String], in directory: String) -> String {
        (["git", "-C", directory] + arguments).map(shellWord).joined(separator: " ")
    }

    /// A word as the shell should read it: bare when it is only characters no shell treats
    /// specially, else in single quotes — POSIX quoting, which fish reads the same way
    /// (`TerminalTmux.quoted`).
    nonisolated static func shellWord(_ word: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./=:,@%+")
        if !word.isEmpty, word.unicodeScalars.allSatisfy(plain.contains) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
