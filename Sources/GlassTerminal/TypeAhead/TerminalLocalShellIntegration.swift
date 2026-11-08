//
//  TerminalLocalShellIntegration.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): this Mac's own zsh terminals mark their prompts without anyone editing a file.
//  The pane starts zsh with `ZDOTDIR` at a small folder of the app's, which puts the person's own `ZDOTDIR` back, reads
//  their start-up files as zsh would, then loads the integration (`TerminalShellIntegration.localZshStartupFiles`), as
//  VS Code and Ghostty do. A terminal in tmux gets the same through its session's environment (`new-session -e`,
//  `tmuxEnvironment`), never the server's: a shell already running in tmux before then has none.
//  Settings ▸ Suggestions turns it off. `tasks/2026-11/2026-11-06_type-ahead.md`, "Installing the integration".
//

#if os(macOS)
import Foundation
import GlassLayers
import os

@MainActor
enum TerminalLocalShellIntegration {
    private static let logger = Logger(subsystem: "sh.glas", category: "shell-integration")
    /// Written once a run: the files the app's version carries.
    private static var written: URL?
    /// Where the start-up folder goes: the app's Application Support folder, nil outside the app (a test process
    /// never writes into the person's own; its tests set a folder of their own).
    static var baseFolder: URL? = Bundle.main.bundleURL.pathExtension == "app"
        ? TerminalCommandHistory.defaultFolder()?.deletingLastPathComponent() : nil {
        didSet { written = nil }
    }

    /// `environment` for starting `shellPath`: with the integration's for zsh while the setting allows it,
    /// unchanged otherwise (another shell, the setting off, or the folder couldn't be written).
    static func environment(_ environment: [String: String], shellPath: String?) -> [String: String] {
        guard let shellPath, TerminalShellKind(path: shellPath) == .zsh,
              TerminalTypeAheadSettings.load(from: GlassUITestRun.settingsDefaults).integratesThisMac,
              let folder = startupFolder() else { return environment }
        return TerminalShellIntegration.localZshEnvironment(startupFolder: folder.path, inherited: environment)
    }

    /// For a terminal in tmux: an environment as `environment(_:shellPath:)` made it (`NAME=value`), split
    /// into the session's own variables, for `new-session -e`, and the rest, for the server and its
    /// clients (`TerminalShellIntegration.tmuxSessionVariables`).
    static func tmuxEnvironment(_ environment: [String]) -> (session: [String], rest: [String]) {
        guard let folder = startupFolder() else { return ([], environment) }
        var variables: [String: String] = [:]
        for entry in environment {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            variables[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        let split = TerminalShellIntegration.tmuxSessionVariables(variables, startupFolder: folder.path)
        let pairs: ([String: String]) -> [String] = { $0.map { "\($0.key)=\($0.value)" }.sorted() }
        return split.session.isEmpty ? ([], environment) : (pairs(split.session), pairs(split.rest))
    }

    /// The start-up folder, written when its files differ from the app's.
    static func startupFolder() -> URL? {
        if let written { return written }
        guard let base = baseFolder else { return nil }
        let folder = base.appendingPathComponent("Shell Integration/zsh", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, contents) in TerminalShellIntegration.localZshStartupFiles() {
                let url = folder.appendingPathComponent(name)
                let data = Data(contents.utf8)
                if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
            }
            written = folder
            return folder
        } catch {
            logger.error("This Mac's zsh starts without shell integration: its folder could not be written: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
