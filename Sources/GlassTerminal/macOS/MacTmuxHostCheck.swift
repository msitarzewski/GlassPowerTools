//
//  MacTmuxHostCheck.swift
//  Glass Power Tools — GlassTerminal
//
//  Whether the host local terminals run in (D66) is still the app on disk (2026-11-23). The host is
//  the app's own executable, run by launchd, and it outlives quits and updates by design. An update
//  replaces that executable under it: the code it runs is the old one, and macOS's check of it fails
//  ("the code on disk does not match what is running", `errSecCSStaticCodeChanged`). Every program
//  in its terminals answers to it for privacy permissions, and macOS then refuses them folders.
//  Seen in the macOS VM with SIP on (0.4.623 updated to 0.4.632 under its host): Desktop and
//  Downloads at once, with no prompt, where before the update the same host was asked; Documents,
//  allowed before the update, still read for a few minutes and was refused ten minutes on. A report:
//  Claude Code in a local terminal could no longer read Documents, Desktop or Downloads, through a
//  quit and reopen, with the app's switches on in Privacy & Security. Ending the host is the way
//  out: a host started again from the updated app read Documents at once and was asked for Desktop.
//
//  So on opening, the app looks at the host this Mac's tmux runs under and, when an update has
//  replaced it, says so and offers to end its terminals (`MacLaunchReopen`); Settings ▸ Terminal
//  says it too. Since 0.4.646 the host runs from a copy no update replaces (`MacTmuxHostCopy`), so
//  this finds only a host an earlier version started, once; asking at every update was no answer.
//  Since 0.4.648 the host is a small app of its own with the app's bundle ID and signature (D115),
//  checked the same way; it is replaced only when it runs from inside the app, when no copy could be made.
//

#if os(macOS)
import Darwin
import Foundation
import GlassLayers
import Security

nonisolated enum MacTmuxHostCheck {
    /// What macOS says of a running program's code.
    enum CodeState: Equatable, Sendable {
        /// It is what is on disk.
        case intact
        /// Its file was replaced after it started, as an update replaces the app: macOS's privacy
        /// permissions no longer recognise it.
        case replaced
        /// Another answer, by its code.
        case other(OSStatus)
    }

    /// A host an update has replaced, with the terminals running under it.
    struct ReplacedHost: Equatable, Sendable {
        let pid: pid_t
        /// When it started, from the system: with `pid`, which host this is.
        let started: Int
        let terminals: Int

        /// Kept when the person says Not Now, so the same host is mentioned at one launch only.
        var key: String { "\(pid)@\(started)" }
    }

    static let dismissedKey = "MacTmuxHostCheck.dismissedHost"

    /// The state of process `pid`'s code, when it is signed as `identifier`; nil when it isn't, or
    /// isn't running.
    static func codeState(pid: pid_t, identifier: String) -> CodeState? {
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &guest) == errSecSuccess,
              let guest, signingIdentifier(of: guest) == identifier else { return nil }
        let validity = SecCodeCheckValidity(guest, [], nil)
        switch validity {
        case errSecSuccess: return .intact
        case errSecCSStaticCodeChanged: return .replaced
        default: return .other(validity)
        }
    }

    /// The identifier the running code was signed with, read from the process itself, so a file
    /// replaced or gone since doesn't answer for it.
    static func signingIdentifier(of code: SecCode) -> String? {
        var information: CFDictionary?
        // A dynamic code object is accepted here in place of a static one (the call's
        // documentation); Swift's types don't say so.
        guard SecCodeCopySigningInformation(unsafeBitCast(code, to: SecStaticCode.self),
                                            SecCSFlags(rawValue: kSecCSDynamicInformation), &information) == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String
    }

    /// The tmux server's process, from its own answer to `list-sessions -F '#{pid}'` (a line a
    /// session, each the server's); nil from no answer.
    static func serverPID(listing: String?) -> pid_t? {
        listing?.split(whereSeparator: \.isNewline)
            .lazy.compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
            .first { $0 > 1 }
    }

    /// The sessions in that answer.
    static func sessionCount(listing: String?) -> Int {
        listing?.split(whereSeparator: \.isNewline).count ?? 0
    }

    /// The process that started `pid` and when `pid` started; no parent when launchd started it.
    static func process(_ pid: pid_t) -> (parent: pid_t?, started: Int)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let parent = pid_t(info.pbi_ppid)
        return (parent > 1 ? parent : nil, Int(info.pbi_start_tvsec))
    }

    /// This Mac's tmux server's host, when it is this app's and an update has replaced it. A
    /// server tmux started itself (before D66, or when launchd wouldn't) has no host to check.
    static func replacedHost(listing: String?, identifier: String) -> ReplacedHost? {
        guard let server = serverPID(listing: listing), let host = process(server)?.parent,
              let started = process(host)?.started,
              codeState(pid: host, identifier: identifier) == .replaced else { return nil }
        return ReplacedHost(pid: host, started: started, terminals: sessionCount(listing: listing))
    }

    /// The host of this Mac's own tmux, asked without starting a server; nil when local terminals
    /// aren't kept in tmux, none run, or its host is intact.
    static func current(server: MacLocalTmux.Server, defaults: UserDefaults = GlassUITestRun.settingsDefaults,
                        identifier: String? = Bundle.main.bundleIdentifier) -> ReplacedHost? {
        guard defaults.bool(forKey: UserDefaultsKeys.localTmux), let identifier,
              let tmux = server.executablePath() else { return nil }
        return replacedHost(listing: server.serverProcess(tmux), identifier: identifier)
    }

    /// What opening the app says while such a host runs: what's wrong, for what, and the way out.
    static func notice(terminals: Int) -> (title: String, message: String, end: String) {
        let one = terminals == 1
        let running = one ? "1 local terminal was" : "\(terminals) local terminals were"
        let they = one ? "it" : "they", them = one ? "it" : "them"
        return ("Terminals from before the update can't open some folders",
                "Glass Power Tools was updated while \(running) running. Until \(they) \(one ? "ends" : "end"), "
                + "macOS can refuse programs in any local terminal your Documents, Desktop and Downloads folders, "
                + "even with the app's permission on. Ending \(them) fixes this. Whatever is running in \(them) "
                + "stops, and the next terminal starts afresh.",
                one ? "End Terminal" : "End \(terminals) Terminals")
    }

    /// Settings ▸ Terminal's line under the status, while the host is a replaced one.
    static let settingsNote = "Started before the app was updated: macOS can refuse programs in these terminals your "
        + "Documents, Desktop and Downloads folders. End them to fix it."
}
#endif
