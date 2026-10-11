//
//  MacLocalShellFolder.swift
//  Glass Power Tools — GlassTerminal
//
//  Open Folder Here on a local pane (2026-10-08): the folder the shell is in, or a plain "not
//  known". A new local terminal opened from this one asks the same, to start there (W37,
//  `MacLocalTerminalStart`). The button used to fall back to the tmux client's folder and then
//  Home, so a pane in tmux opened Home whenever tmux did not answer, and a deleted folder did
//  nothing at all. No answer is unknown, never a stale value (967749f's rule), and every failure
//  says what to do.
//

#if os(macOS)
import Foundation
import os

nonisolated enum MacLocalShellFolder: Equatable, Sendable {
    /// A folder that exists.
    case folder(String)
    /// The shell is in a folder that has since been moved or deleted.
    case missing(String)
    /// Nothing reliable answered: tmux did not, or the shell has exited.
    case unknown

    /// Where the shell is standing, whether or not the folder is still there.
    var path: String? {
        switch self {
        case .folder(let path), .missing(let path): path
        case .unknown: nil
        }
    }

    /// What is asked, injected so tests need neither tmux nor particular folders.
    struct Lookups: Sendable {
        /// tmux's `pane_current_path` for a session — the folder of whatever runs in its active
        /// pane, the same answer that names the tab — or nil when tmux did not answer.
        var tmuxDirectory: @Sendable (_ session: String) -> String?
        /// Whether a path is a folder that exists.
        var isFolder: @Sendable (_ path: String) -> Bool

        static let live = Lookups(
            tmuxDirectory: { session in
                MacLocalTmux.executablePath().flatMap { MacLocalTmux.context(session: session, tmux: $0)?.directory }
            },
            isFolder: { path in
                var isDirectory = ObjCBool(false)
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
        )
    }

    /// Whether there is anything to ask: a shell that has exited is in no folder, but a tmux
    /// session can outlive the client this pane ran, so it is still asked.
    static func isAvailable(tmuxSession: String?, shellIsRunning: Bool) -> Bool {
        tmuxSession != nil || shellIsRunning
    }

    /// Where a local pane's shell is.
    /// - Parameters:
    ///   - tmuxSession: the session the pane runs in, or nil for a plain shell.
    ///   - shellIsRunning: whether the pane's own process is running.
    ///   - processDirectory: the shell process's folder (`proc_pidinfo`), else what the shell
    ///     reported (OSC 7) — `SwiftTermLocalProcessRuntime.currentWorkingDirectory`. Read only
    ///     for a plain shell that is running.
    @MainActor
    static func resolve(tmuxSession: String?, shellIsRunning: Bool,
                        processDirectory: () -> String?,
                        lookups: Lookups = .live) async -> MacLocalShellFolder {
        let source: Source
        if let tmuxSession {
            // The process here is the tmux client, which stays where the session started; only
            // tmux knows where the shell is now.
            source = .tmux(tmuxSession)
        } else if isAvailable(tmuxSession: nil, shellIsRunning: shellIsRunning) {
            source = .path(processDirectory())
        } else {
            // The runtime still holds the exited shell's last folder; that is not where anything is.
            source = .path(nil)
        }
        return await classify(source, lookups: lookups)
    }

    private enum Source: Sendable {
        case tmux(String)
        case path(String?)
    }

    /// Off the main actor: asking tmux spawns it, and a folder on a slow volume can take a while
    /// to look at.
    @concurrent
    private static func classify(_ source: Source, lookups: Lookups) async -> MacLocalShellFolder {
        let path: String?
        switch source {
        case .tmux(let session):
            path = lookups.tmuxDirectory(session)
            if path == nil { logger.error("The shell's folder: tmux gave none for \(session, privacy: .public)") }
        case .path(let reported):
            path = reported
        }
        guard let path, path.hasPrefix("/") else { return .unknown }
        guard lookups.isFolder(path) else {
            logger.notice("The shell's folder is gone: \(path, privacy: .private)")
            return .missing(path)
        }
        return .folder(path)
    }

    /// What the pane says when the folder does not open: what happened, and what to do.
    struct Problem: Equatable, Sendable {
        let title: String
        let message: String
    }

    /// Opens a folder that exists in Finder. Anything else, including the opener's refusal, comes
    /// back as a message to show; nothing fails silently.
    /// - Parameter opener: `NSWorkspace.open`, whose false is all it says about a failure.
    @MainActor
    static func open(_ folder: MacLocalShellFolder, with opener: (URL) -> Bool) -> Problem? {
        switch folder {
        case .folder(let path):
            // `open`, not `activateFileViewerSelecting`: selecting shows the folder highlighted
            // inside its *parent*, which is the wrong place — the point of the control is to
            // arrive where the shell already is. Opening the URL shows that directory's contents.
            guard opener(URL(filePath: path, directoryHint: .isDirectory)) else {
                logger.error("Open Folder Here: the system did not open \(path, privacy: .private)")
                return Problem(
                    title: "Couldn’t Open the Folder",
                    message: "Finder didn’t open “\(displayed(path))”. Try again, or type “open .” in the terminal."
                )
            }
            return nil
        case .missing(let path):
            return Problem(
                title: "This Folder No Longer Exists",
                message: "The shell is in “\(displayed(path))”, which may have been moved or deleted. Use cd to go to a folder that exists, then try again."
            )
        case .unknown:
            return Problem(
                title: "Couldn’t Find This Shell’s Folder",
                message: "Try again in a moment, or type “open .” in the terminal."
            )
        }
    }

    private static func displayed(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private static let logger = Logger(subsystem: "sh.glas", category: "terminal")
}
#endif
