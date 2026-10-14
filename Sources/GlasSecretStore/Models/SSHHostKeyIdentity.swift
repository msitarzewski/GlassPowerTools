//
//  SSHHostKeyIdentity.swift
//  GlasSecretStore
//
//  Whether a saved machine is this one, by the only evidence that proves it: the SSH host key it
//  presents. A host key's private half lives on one machine, so a key pinned for a saved machine
//  that is also one of this machine's own (`/etc/ssh/ssh_host_*_key.pub`) means the saved machine
//  is this one. Names and addresses prove nothing — one machine answers to many, and many machines
//  share `127.0.0.1` — and no match means "not known to be this machine", never "another machine":
//  a Mac with Remote Login off has no host keys at all.
//
//  Used by the editor (a project on this machine is read directly, not over SSH to itself,
//  `GlassMachineIdentity`) and by the terminal (a terminal handed off from another device to this
//  Mac continues in this Mac's own tmux tab, D72).
//

import Foundation

public enum SSHHostKeyIdentity {
    /// Where macOS keeps the host keys `sshd` presents. Readable by anyone; the private halves beside
    /// them are not, and are never touched.
    public static let hostKeyDirectory = "/etc/ssh"

    /// This machine's public host key lines, one per key file. Empty on a device with none — every
    /// iPhone and Vision Pro, and a Mac that has never had Remote Login on.
    public static func localHostKeyLines(directory: String = hostKeyDirectory,
                                         fileManager: FileManager = .default) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        return names.filter { $0.hasPrefix("ssh_host_") && $0.hasSuffix("_key.pub") }.sorted().compactMap { name in
            try? String(contentsOfFile: (directory as NSString).appendingPathComponent(name), encoding: .utf8)
        }
    }

    /// This machine's host keys as their base64 wire-format blobs — the form host trust pins them in.
    public static func localHostKeys(directory: String = hostKeyDirectory) -> Set<String> {
        Set(localHostKeyLines(directory: directory).compactMap(blob(inLine:)))
    }

    /// The base64 key in an OpenSSH public key line: `type base64 [comment]`.
    public static func blob(inLine line: String) -> String? {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, Data(base64Encoded: String(fields[1])) != nil else { return nil }
        return String(fields[1])
    }

    /// Whether a machine whose pinned keys are `pinnedKeys` is this one. One shared key is proof.
    public static func isThisMachine(pinnedKeys: Set<String>, localKeys: Set<String>) -> Bool {
        guard !pinnedKeys.isEmpty, !localKeys.isEmpty else { return false }
        return !pinnedKeys.isDisjoint(with: localKeys)
    }
}
