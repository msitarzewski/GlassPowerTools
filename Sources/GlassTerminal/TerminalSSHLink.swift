//
//  TerminalSSHLink.swift
//  Glass Power Tools — GlassTerminal
//
//  An `ssh://` link opened with Glass Power Tools — from a browser, a chat, a document (D72,
//  2026-10-13; the owner approved Glass Power Tools handling them). The form is
//  `ssh://[user[;fingerprint]@]host[:port]` (the IETF secsh URI draft, as other SSH clients read
//  it); anything after the host — a path, a query — is not part of where to connect, and is not
//  used. The fingerprint parameter is not trusted from a link: host trust is decided as for every
//  connection, by the prompt or the pin.
//
//  A machine already in the library connects as it is saved. One that is not opens the new-server
//  form, filled in: a link names a machine, not a way to sign in to it.
//

import Foundation

struct TerminalSSHLink: Equatable {
    let host: String
    let port: Int
    let user: String?

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "ssh",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty
        else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "/" }) else { return nil }
        let port = components.port ?? 22
        guard (1...65_535).contains(port) else { return nil }
        // `user;fingerprint=…`: the user alone.
        let user = components.percentEncodedUser
            .map { $0.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? $0 }
            .flatMap { $0.removingPercentEncoding }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.host = host
        self.port = port
        self.user = user
    }

    /// The saved server it names: the same host and port, and the same user when the link has one.
    /// With no user in the link, the first saved one for that host and port.
    func match(in servers: [ServerConfiguration]) -> ServerConfiguration? {
        let candidates = servers.filter {
            SSHConnection.normalizedHost($0.host).lowercased() == host.lowercased() && $0.port == port
        }
        guard let user else { return candidates.first }
        return candidates.first { $0.username == user }
    }

    /// The new-server form's starting point for a machine not in the library.
    var draft: ServerConfiguration {
        ServerConfiguration(name: host, host: host, port: port, username: user ?? "")
    }
}
