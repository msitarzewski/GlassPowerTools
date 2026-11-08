//
//  TerminalShellIntegrationInstaller.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06): the shell integration on a server, installed or removed when the person asks
//  (Settings ▸ Suggestions), over a connected terminal's own SSH. Installing writes the script for the account's
//  shell to `~/.config/glasspowertools/` and adds one marked line to that shell's start-up file; removing takes
//  out that line, and only it, and the script. `TerminalShellIntegration` plans the edits; this does the I/O.
//  `tasks/2026-11/2026-11-06_type-ahead.md`, "Installing the integration".
//
//  A start-up file is the person's, and a damaged one can lock them out of a working shell, so no surprises
//  (the owner, 2026-11-06):
//  - Installing only appends to it, as iTerm2's installer does (`echo … >> ~/.bashrc`). It is never rewritten, so
//    whatever happens to the connection, what was there stays. What it holds afterwards is read back and checked.
//  - Removing replaces it with the Files editor's own verified save (`SFTPBrowserView.uploadRemoteEditorBytes`):
//    the new text is written beside it and renamed over it in one step, and only if the file is still what was
//    read. A start-up file linked from elsewhere (a dotfiles folder) is changed where it lives; the link stays.
//  - A file that isn't UTF-8 text is never edited.
//

import Foundation
import GlassSSHTransport
import NIOCore
import NIOFoundationCompat

@MainActor
enum TerminalShellIntegrationInstaller {
    enum State: Equatable, Sendable {
        /// Our line is in the shell's start-up file.
        case installed(TerminalShellKind)
        /// Not installed; `others` names another terminal's integration the file already loads.
        case notInstalled(TerminalShellKind, others: [String])
        /// The account's shell isn't one the integration knows (its path, when read).
        case unsupported(String?)
    }

    enum Failure: LocalizedError {
        case notConnected
        case unsupportedShell(String?)
        /// The start-up file isn't UTF-8 text: it is left as it is.
        case notText(String)
        /// The start-up file didn't hold what was planned once the line was added.
        case notAsPlanned(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: "Connect a terminal to this machine first: the integration is installed over that connection."
            case .unsupportedShell(let path):
                "This account's shell (\(path ?? "unknown")) isn't zsh, bash or fish, so its prompts can't be marked."
            case .notText(let path):
                "~/\(path) isn't plain text the app can edit safely, so it was left as it is. To mark prompts, add the "
                    + "line from Settings ▸ Suggestions to it yourself."
            case .notAsPlanned(let path):
                "~/\(path) changed while the line was being added. Open it and check its last lines before your next login."
            }
        }
    }

    /// What the installer needs of a machine: a command run, and its files over SFTP (paths relative to the
    /// account's home, where SFTP starts). `serverID` names the machine for the Files editor's save.
    struct Remote: Sendable {
        let serverID: UUID
        let run: @Sendable (String) async throws -> String
        let openClient: @Sendable () async throws -> SFTPClient

        static func session(_ session: TerminalSession) -> Remote {
            Remote(
                serverID: session.server.id,
                run: { [weak session] command in
                    guard let connection = await session?.getSSHConnection() else { throw Failure.notConnected }
                    return try await connection.executeRemoteCommand(command, maxResponseBytes: 4_096,
                                                                     executionTimeout: .seconds(15))
                },
                openClient: { [weak session] in
                    guard let session else { throw Failure.notConnected }
                    return try await TerminalRemoteDrops.openClient(for: session)
                })
        }
    }

    static func state(of session: TerminalSession) async -> State { await state(of: .session(session)) }
    static func install(on session: TerminalSession) async throws { try await install(on: .session(session)) }
    static func remove(from session: TerminalSession) async throws { try await remove(from: .session(session)) }

    /// The account's login shell, from `$SHELL`.
    static func shell(of remote: Remote) async -> (kind: TerminalShellKind?, path: String?) {
        guard let path = try? await remote.run("printf '%s' \"$SHELL\"").trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return (nil, nil) }
        return (TerminalShellKind(path: path), path)
    }

    static func state(of remote: Remote) async -> State {
        let (kind, path) = await shell(of: remote)
        guard let kind, let client = try? await remote.openClient() else { return .unsupported(path) }
        let rc = await read(TerminalShellIntegration.rcPath(for: kind), through: client)
        try? await client.close()
        if let rc, TerminalShellIntegration.addingSourceLine(to: rc, shell: kind) == nil { return .installed(kind) }
        return .notInstalled(kind, others: rc.map(TerminalShellIntegration.otherIntegrations(in:)) ?? [])
    }

    /// Writes the script and adds the line; terminals opened afterwards mark their prompts.
    static func install(on remote: Remote) async throws {
        let (kind, path) = await shell(of: remote)
        guard let kind else { throw Failure.unsupportedShell(path) }
        let client = try await remote.openClient()
        do {
            let scriptPath = TerminalShellIntegration.remoteScriptPath(for: kind)
            try await makeFolders(for: scriptPath, through: client)
            try await write(TerminalShellIntegration.script(for: kind), to: scriptPath, through: client)
            let rcPath = TerminalShellIntegration.rcPath(for: kind)
            try await makeFolders(for: rcPath, through: client)
            try await addLine(for: kind, to: rcPath, through: client)
            try? await client.close()
        } catch {
            try? await client.close()
            throw error
        }
    }

    /// The line added to the end of the start-up file, and nothing else touched: the plan is checked to be only an
    /// addition, the file is opened to append, and what it holds afterwards is read back.
    private static func addLine(for kind: TerminalShellKind, to rcPath: String, through client: SFTPClient) async throws {
        let current = try await readStartupFile(rcPath, through: client)
        guard let updated = TerminalShellIntegration.addingSourceLine(to: current?.text, shell: kind) else { return }
        let planned = Data(updated.utf8)
        let existing = current?.observation.data ?? Data()
        guard planned.starts(with: existing) else { throw Failure.notAsPlanned(rcPath) }
        let addition = planned.dropFirst(existing.count)
        let file = current == nil
            ? try await client.openFile(filePath: rcPath, flags: [.write, .create, .exclusive])
            : try await client.openFile(filePath: rcPath, flags: [.write, .append])
        do {
            try await file.write(ByteBuffer(data: Data(addition)), at: UInt64(existing.count))
            try await file.close()
        } catch {
            try? await file.close()
            throw error
        }
        guard try await readStartupFile(rcPath, through: client)?.observation.data == planned else {
            throw Failure.notAsPlanned(rcPath)
        }
    }

    /// Takes out the line and the script.
    static func remove(from remote: Remote) async throws {
        let (kind, path) = await shell(of: remote)
        guard let kind else { throw Failure.unsupportedShell(path) }
        let client = try await remote.openClient()
        do {
            try await removeLine(for: kind, through: client, serverID: remote.serverID)
            let scriptPath = TerminalShellIntegration.remoteScriptPath(for: kind)
            try? await client.remove(at: scriptPath)
            // The app's folder too, once nothing else is in it (a server refuses to remove one that isn't empty).
            try? await client.rmdir(at: (scriptPath as NSString).deletingLastPathComponent)
            try? await client.close()
        } catch {
            try? await client.close()
            throw error
        }
    }

    /// The line taken out of the start-up file, with the Files editor's verified save: written beside the file and
    /// renamed over it, only if the file is still what was read. A file left holding nothing (the install made it)
    /// is removed, unless it is a link's target.
    private static func removeLine(for kind: TerminalShellKind, through client: SFTPClient, serverID: UUID) async throws {
        let rcPath = TerminalShellIntegration.rcPath(for: kind)
        let isLink = (try? await client.getLinkAttributes(at: rcPath))?.fileType == .symbolicLink
        // A linked file (a dotfiles folder) is changed where it lives; the link stays.
        let target = isLink ? try await client.getRealPath(atPath: rcPath) : rcPath
        guard let current = try await readStartupFile(target, through: client),
              let updated = TerminalShellIntegration.removingSourceLine(from: current.text, shell: kind) else { return }
        if updated.isEmpty, !isLink {
            try await client.remove(at: target)
            return
        }
        let folder = (target as NSString).deletingLastPathComponent
        _ = try await SFTPBrowserView.uploadRemoteEditorBytes(
            Data(updated.utf8), client: client, serverID: serverID,
            remoteDirectory: folder.isEmpty ? "." : folder, filename: (target as NSString).lastPathComponent,
            targetPath: target, expectedRemote: current.observation, maximumBytes: startupFileLimit)
    }

    // MARK: - SFTP

    /// Larger than any start-up file a person writes by hand; a file bigger than this is left alone.
    static let startupFileLimit: UInt64 = 4 * 1_024 * 1_024

    /// A start-up file read whole and checked as the Files editor reads one (a regular file, unchanged while read),
    /// or nil where there is none. Not UTF-8: refused.
    private static func readStartupFile(_ path: String, through client: SFTPClient) async throws
        -> (text: String, observation: SFTPRemoteFileObservation)? {
        let observation: SFTPRemoteFileObservation
        do {
            observation = try await SFTPBrowserView.readVerifiedRemoteObservation(
                client: client, path: path, maximumBytes: startupFileLimit)
        } catch where SFTPSessionError.isMissingPath(error) {
            return nil
        }
        guard let text = String(data: observation.data, encoding: .utf8) else { throw Failure.notText(path) }
        return (text, observation)
    }

    /// What a file holds as text, or nil where it can't be read: for showing whether the line is there.
    static func read(_ path: String, through client: SFTPClient) async -> String? {
        guard let file = try? await client.openFile(filePath: path, flags: .read) else { return nil }
        let buffer = try? await file.readAll()
        try? await file.close()
        return buffer.map { String(decoding: Data(buffer: $0), as: UTF8.self) }
    }

    /// Replaces the file's contents; a file that exists keeps its permissions.
    private static func write(_ text: String, to path: String, through client: SFTPClient) async throws {
        let file = try await client.openFile(filePath: path, flags: [.write, .create, .truncate])
        do {
            try await file.write(ByteBuffer(data: Data(text.utf8)))
            try await file.close()
        } catch {
            try? await file.close()
            throw error
        }
    }

    /// Each folder on the way to `path`, made where missing.
    private static func makeFolders(for path: String, through client: SFTPClient) async throws {
        var folder = ""
        for part in path.split(separator: "/").dropLast() {
            folder += folder.isEmpty ? String(part) : "/" + part
            if (try? await client.getAttributes(at: folder)) == nil {
                try await client.createDirectory(atPath: folder)
            }
        }
    }
}
