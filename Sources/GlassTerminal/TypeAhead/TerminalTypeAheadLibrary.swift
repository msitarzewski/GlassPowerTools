//
//  TerminalTypeAheadLibrary.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead's library source (D102, 2026-11-06): the machines in the library, for the commands that reach one.
//  `ssh`, `mosh`, `sftp` and the like take `user@address` (with `-p` where the port isn't 22), `scp` and `rsync`
//  `user@address:` for a path there, `ping`, `dig` and the like the address alone. The library's names aren't
//  always names the shell can resolve; its addresses are. `tasks/2026-11/2026-11-06_type-ahead.md`, source 4.
//

import Foundation

nonisolated enum TerminalTypeAheadLibrary {
    /// A machine as the commands need it.
    struct Machine: Equatable, Sendable {
        var address: String
        var user: String
        var port: Int
        /// Used lately: offered first.
        var lastConnected: Date?
    }

    private static let logins: Set<String> = ["ssh", "mosh", "sftp", "ssh-copy-id", "autossh"]
    private static let copies: Set<String> = ["scp", "rsync"]
    private static let addresses: Set<String> = ["ping", "ping6", "traceroute", "mtr", "dig", "host", "nslookup",
                                                 "nc", "telnet", "curl", "wget", "whois"]
    /// Words before the command that leave it the command: `sudo ssh …`, `env X=1 ssh …`, `time ssh …`.
    private static let prefixes: Set<String> = ["sudo", "env", "time", "nice", "command", "exec", "nohup"]

    /// Words for the word being typed on `line`, from `machines`.
    static func words(line: String, machines: [Machine], now: Date = Date()) -> [(word: String, score: Double)] {
        let (base, word) = TerminalTypeAheadEngine.currentWord(of: line)
        // A flag, or a path, isn't where a machine goes.
        guard !word.hasPrefix("-"), !word.hasPrefix("/"), !word.hasPrefix("."), !word.hasPrefix("~") else { return [] }
        let before = base.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let command = before.first(where: { !prefixes.contains($0) && !$0.contains("=") }) else { return [] }
        // The word after an option that takes a value (`ssh -i key`, `scp -P 2222`) is that value.
        if let last = before.last, last.hasPrefix("-"), last.count == 2, "iopPlFJcbDeEmQRSWw".contains(last.last!) { return [] }

        let ordered = machines.sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
        func score(_ machine: Machine, rank: Int) -> Double {
            let lately = machine.lastConnected.map { 1 / (1 + max(0, now.timeIntervalSince($0)) / 86_400) } ?? 0
            return 1.2 + lately - Double(rank) * 0.01
        }
        var words: [(word: String, score: Double)] = []
        for (rank, machine) in ordered.enumerated() where !machine.address.isEmpty {
            let login = machine.user.isEmpty ? machine.address : "\(machine.user)@\(machine.address)"
            if logins.contains(command) {
                let port = machine.port == 22 ? "" : (command == "mosh" ? " --ssh=\"ssh -p \(machine.port)\"" : " -p \(machine.port)")
                words.append((login + port, score(machine, rank: rank)))
            } else if copies.contains(command) {
                words.append((login + ":", score(machine, rank: rank)))
            } else if addresses.contains(command) {
                words.append((machine.address, score(machine, rank: rank)))
            }
        }
        return words
    }
}
