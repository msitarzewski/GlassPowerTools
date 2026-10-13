//
//  GlassLocalNetworkAccess.swift
//  Glass Power Tools — GlassShell
//
//  Whether a failed connection could be the system keeping the app off the local network, and
//  what to tell the user when it could. One rule for every capability that connects to a machine
//  (2026-10-13): the terminal had the measured one (B-X13), and the database kept its own, which
//  looked for EPERM/EACCES and so never matched what a denial actually is.
//
//  **Measured** from a test process without Local Network access, against a machine on the local
//  network: the SSH engine, MySQLNIO and PostgresNIO all fail at once with "No route to host"
//  (EHOSTUNREACH, errno 65) — PostgresNIO inside a `PSQLError` whose plain description hides it,
//  so the reflected description is read too. A refused port is errno 61; a timeout or a rejected
//  sign-in is the machine answering. Other developers report the same: an immediate EHOSTUNREACH
//  until the app is allowed (https://developer.apple.com/forums/thread/765285). A Bonjour lookup
//  the system refuses waits with kDNSServiceErr_PolicyDenied, -65570 ("policy denied"; TN3179,
//  https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
//
//  "No route" also means the machine is off, so the advice is a *may*.
//

import Foundation

public enum GlassLocalNetworkAccess {
    /// Whether `error` could be a Local Network denial.
    public static func mayBeDenial(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EHOSTUNREACH) { return true }
        if nsError.code == -65_570 { return true }
        let raw = (String(describing: error) + "\n" + String(reflecting: error)).lowercased()
        return raw.contains("no route to host") || raw.contains("(errno: 65)") || raw.contains("policy denied")
    }

    /// Whether `rawHost` names a machine the Local Network permission governs: a private or
    /// link-local address, or a `.local` name. Loopback is included as it always was here; the
    /// system never denies it, so `mayBeDenial` is what keeps the advice off a loopback failure.
    public static func isLikelyLocalHost(_ rawHost: String) -> Bool {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }

        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }

        if host.contains(":") {
            let address = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
            return address == "::1"
                || address.hasPrefix("fc")
                || address.hasPrefix("fd")
                || address.hasPrefix("fe8")
                || address.hasPrefix("fe9")
                || address.hasPrefix("fea")
                || address.hasPrefix("feb")
        }

        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let values = octets.compactMap { Int($0) }
        guard octets.count == 4,
              values.count == 4,
              values.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }

        return values[0] == 10
            || values[0] == 127
            || (values[0] == 169 && values[1] == 254)
            || (values[0] == 172 && (16...31).contains(values[1]))
            || (values[0] == 192 && values[1] == 168)
    }

    /// What to do about it, in the platform's own words for where the switch is.
    public static var advice: String {
        #if os(macOS)
        let settings = "System Settings"
        #else
        let settings = "Settings"
        #endif
        return "If the machine is on, Glass Power Tools may not be allowed on the local network. In \(settings), open Privacy & Security > Local Network, allow Glass Power Tools, then try again."
    }
}
