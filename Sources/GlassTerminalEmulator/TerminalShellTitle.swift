//
//  TerminalShellTitle.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  The folder a prompt's title names (2026-11-09; the owner, on an SSH tab to an Ubuntu server with no folder
//  button: "Where is my folder icon for this connection!?"). Open Folder Here wants the folder a shell is standing
//  in. A shell that sends OSC 7 says so outright; bash on a Linux server sends nothing of the kind, but its
//  distribution's start-up files set the window title at every prompt, with the folder in it:
//  - Debian and Ubuntu, `~/.bashrc` from `/etc/skel`: `\u@\h: \w`, so `ann@box: ~/src` or `ann@box: /var/www/shop`;
//  - Fedora's `/etc/bashrc` and Arch's `/etc/bash.bashrc`: `%s@%s:%s` of `$USER`, the short host name and
//    `${PWD/#$HOME/\~}`, so `ann@box:~/src`.
//  Only that shape is read. A program's own title (`vim notes.txt`, Codex's), a Debian chroot's
//  `(name)ann@box: …`, and a folder bash shortened (`PROMPT_DIRTRIM`'s `~/.../src`) name no folder this terminal's
//  host can open.
//

import Foundation

public nonisolated enum TerminalShellTitle {
    /// A folder a title named: the account the title names, and the folder, `/…`, `~` or `~/…`. A `~` is that
    /// account's home, so it means a folder only for the same account.
    public struct Folder: Equatable, Sendable {
        public let user: String
        public let path: String

        public init(user: String, path: String) {
            self.user = user
            self.path = path
        }
    }

    /// The folder in `title`, when the title has a prompt's shape. Nil for anything else.
    public static func folder(in title: String?) -> Folder? {
        guard let title, let match = title.wholeMatch(of: shape) else { return nil }
        let path = String(match.folder)
        guard !path.split(separator: "/").contains("...") else { return nil }
        return Folder(user: String(match.user), path: path)
    }

    /// `user@host: folder` or `user@host:folder`; the user and host without spaces, colons or a chroot's
    /// parentheses, and the folder from `/` or `~` to the end of the title.
    nonisolated(unsafe) private static let shape = #/^(?<user>[^\s@:()]+)@[^\s@:/()]+: ?(?<folder>~|~/.*|/.*)$/#
}
