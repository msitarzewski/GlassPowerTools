//
//  TerminalPathActions.swift
//  Glass Power Tools — GlassTerminal
//
//  A path a terminal on a host printed, found on that host, and what the terminal's link menu does
//  with it: Open in Editor, Show in Files (the owner, 2026-10-14: "Can we datadetector a path and
//  open a path with a context menu?"). The Mac's windows did this for their panes
//  (`MacWorkspaceController.locatePath`); on Vision Pro a pinch held on a path offers the same
//  (2026-10-15: "the vision pro needs the data detector and selection work").
//

import Foundation
import GlassTerminalEmulator

extension TerminalSession {
    /// `path` as this terminal printed it, made absolute on its host — `~/…` against the host's
    /// home (tmux's answer where the terminal runs in it, else the host's), a relative path against
    /// the shell's folder — and whether it is a folder. Nil when it is not there, or the host could
    /// not be asked.
    func locate(_ path: String) async -> (path: String, isDirectory: Bool)? {
        var directory: String?
        if TerminalWatchFile.isRelative(path) {
            directory = TerminalRepository.path(fromReported: await workingDirectory(reported: terminalHostModel.currentDirectory))
        }
        var home = tmuxPane?.home
        if path.hasPrefix("~"), home == nil {
            home = (try? await runTmuxCommand("printf '%s' \"$HOME\""))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let absolute = TerminalPathResolution.absolute(path, directory: directory, home: home) else { return nil }
        let kind = try? await runTmuxCommand(
            "if [ -d \(TerminalDroppedPaths.escaped(absolute)) ]; then echo d; elif [ -e \(TerminalDroppedPaths.escaped(absolute)) ]; then echo f; fi")
        switch kind?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "d": return (absolute, true)
        case "f": return (absolute, false)
        default: return nil
        }
    }
}

#if !os(macOS)
@MainActor
enum TerminalPathActions {
    /// The link menu's path actions for a terminal on a host, off the Mac: Open in Editor (a file
    /// as a tab, a folder as a project) and Show in Files (its folder), on the machine it printed
    /// on; and Watch Log File, which `watchFile` carries out in the terminal's window.
    static func install(on session: TerminalSession, watchFile: @escaping @MainActor (String) -> Void) {
        let model = session.terminalHostModel
        let serverID = session.server.id
        model.onOpenPath = { [weak session] path in
            Task { @MainActor in
                guard let found = await session?.locate(path), let runtime = GlassTerminalRuntime.current else { return }
                let open = found.isDirectory ? runtime.openFolderAsProject : runtime.openFileInEditor
                open?(serverID, found.path)
            }
        }
        model.onRevealPath = { [weak session] path in
            Task { @MainActor in
                guard let found = await session?.locate(path) else { return }
                GlassTerminalRuntime.current?.requestFiles(
                    serverID: serverID, at: TerminalPathResolution.folder(of: found.path, isDirectory: found.isDirectory))
            }
        }
        model.revealPathTitle = "Show in Files"
        model.onWatchFile = watchFile
    }
}
#endif
