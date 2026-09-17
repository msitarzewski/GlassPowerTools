//
//  GlassMachineIdentity.swift
//  Glass Power Tools — GlassEditor
//
//  Is this saved SSH connection actually *this* machine?
//
//  The question came from a real workflow: a project is open on the Mac at `~/Software/thing`; the
//  same folder on the same machine is, from the Vision Pro, an SSH connection called juliet. For
//  the project to be one project, a device has to be able to look at a host record and say "that is
//  me" — and then read the files directly instead of dialling itself over the network.
//
//  **The SSH host key is the answer, and nothing else is.**
//
//  - A *hostname* is not identity: two machines are called `juliet.local` on two networks, and
//    the same machine answers to four names.
//  - An *address* is not identity: `192.0.2.10` is a Tailscale address that moves, `127.0.0.1`
//    is every machine, and a LAN address is whatever DHCP said this morning.
//  - A *hardware UUID* would be identity, but only this device's own — there is no way to ask the
//    far end for one without already having a session, which is the thing we are trying to avoid.
//
//  The host key is a public key the machine presents to prove it is itself, it is stable across
//  renames and re-addressing, and this app already collects and pins exactly that (D23). So the
//  comparison is: **does this host's pinned key match a key in this machine's own
//  `/etc/ssh/ssh_host_*_key.pub`?** Same key, same machine.
//
//  What this deliberately does not do is guess. No match means "not known to be this machine",
//  never "another machine" — a Mac with Remote Login switched off publishes no host keys at all, so
//  absence of evidence is common and must not be read as evidence of absence.
//

import Foundation
import CryptoKit
import GlasSecretStore

public enum GlassMachineIdentity {

    /// Where macOS keeps the host keys `sshd` presents. Readable by anyone; the *private* halves
    /// beside them are not, and are never touched here.
    public static let hostKeyDirectory = "/etc/ssh"

    /// This machine's own SSH host key fingerprints, in OpenSSH's `SHA256:…` presentation.
    ///
    /// Empty on a machine with no host keys — including every iPhone and every Vision Pro, and any
    /// Mac that has never had Remote Login enabled. Empty is a normal answer.
    public static func localHostKeyFingerprints(
        directory: String = hostKeyDirectory,
        fileManager: FileManager = .default
    ) -> Set<String> {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        var fingerprints: Set<String> = []
        for name in names where name.hasPrefix("ssh_host_") && name.hasSuffix("_key.pub") {
            let path = (directory as NSString).appendingPathComponent(name)
            guard let line = try? String(contentsOfFile: path, encoding: .utf8),
                  let fingerprint = OpenSSHPublicKeyLine.sha256Fingerprint(in: line) else { continue }
            fingerprints.insert(fingerprint)
        }
        return fingerprints
    }

    /// Whether a host whose SSH key fingerprints are `remoteFingerprints` is this machine.
    ///
    /// Pure, so the decision can be tested without a `/etc/ssh` to read. One shared key is proof:
    /// a host key is unique to the machine that holds its private half.
    public static func isThisMachine(remoteFingerprints: Set<String>,
                                     localFingerprints: Set<String>) -> Bool {
        guard !remoteFingerprints.isEmpty, !localFingerprints.isEmpty else { return false }
        return !remoteFingerprints.isDisjoint(with: localFingerprints)
    }

    /// The same question against this device's real host keys.
    public static func isThisMachine(remoteFingerprints: Set<String>) -> Bool {
        isThisMachine(remoteFingerprints: remoteFingerprints,
                      localFingerprints: localHostKeyFingerprints())
    }

    /// How a project on `hostID` is reached from here.
    ///
    /// - Parameters:
    ///   - hostName: what to call the machine when it is not this one.
    ///   - isLocalHostRecord: the catalog's own answer — the record for "This Mac" (D8) is this
    ///     device by construction, and needs no key comparison at all.
    ///   - remoteFingerprints: the host keys pinned for that machine, if any.
    ///   - hasTerminalService: whether the record carries a terminal service to reach it through.
    public static func reach(hostName: String,
                             isLocalHostRecord: Bool,
                             remoteFingerprints: Set<String>,
                             hasTerminalService: Bool,
                             localFingerprints: Set<String>? = nil) -> GlassEditorProjectReach {
        if isLocalHostRecord { return .thisMachine }
        let local = localFingerprints ?? localHostKeyFingerprints()
        if isThisMachine(remoteFingerprints: remoteFingerprints, localFingerprints: local) {
            return .thisMachine
        }
        return hasTerminalService ? .overSSH(host: hostName) : .unreachable(host: hostName)
    }
}
