//
//  GlassThisMac.swift
//  Glass Power Tools — GlassShell
//
//  D86 (the owner, 2026-10-20: "we don't recognize in the app that 'This Mac' and [his Mac's
//  library record] are one in the same. How can we set that?"): the device's own host and a synced
//  machine that is the same Mac. D8 kept them apart; D50 already wanted the Mac to know its record.
//
//  What this Mac is, to compare a library machine with: its SSH host keys, which Remote Login serves
//  and a terminal on another device pins (`SSHHostKeyIdentity`), and the addresses its interfaces
//  have now with its Bonjour name. A host key is proof; an address is a hint, since a LAN address
//  can pass to another machine — so a match by key links, and a match by address is offered.
//

import Foundation
#if os(macOS)
import Darwin
import SystemConfiguration
#endif

/// How a library machine was found to be this Mac.
public enum GlassThisMacEvidence: Equatable, Sendable {
    /// Its SSH service's pinned host key is this Mac's own.
    case hostKey
    /// Its address is one of this Mac's addresses or names.
    case address(String)
}

public enum GlassThisMac {
    // MARK: What this Mac is

    /// This Mac's addresses and names, as a library machine might be addressed: every interface's
    /// IPv4 and IPv6 address except loopback, and its Bonjour name (`name.local`). Lower case.
    public static func addresses() -> Set<String> {
        var found: Set<String> = []
        #if os(macOS)
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0, let first = list {
            defer { freeifaddrs(list) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = first
            while let entry = cursor {
                defer { cursor = entry.pointee.ifa_next }
                guard let address = entry.pointee.ifa_addr,
                      (entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
                let family = Int32(address.pointee.sa_family)
                guard family == AF_INET || family == AF_INET6 else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
                if getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    found.insert(normalized(String(cString: host)))
                }
            }
        }
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String? {
            found.insert(normalized(name + ".local"))
            found.insert(normalized(name))
        }
        #endif
        return found
    }

    // MARK: Comparing

    /// An address or name as compared: lower case, without brackets, a zone, or a trailing dot.
    public static func normalized(_ address: String) -> String {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("["), text.hasSuffix("]") { text = String(text.dropFirst().dropLast()) }
        if let zone = text.firstIndex(of: "%") { text = String(text[..<zone]) }
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Whether a machine is this Mac, and how that is known: its pinned SSH host key is one of this
    /// Mac's own (`keyMatches`, from `SSHHostKeyIdentity`, which the editor and terminal use too),
    /// else its address is one of this Mac's.
    public static func evidence(address: String?, keyMatches: Bool,
                                thisMacAddresses: Set<String>) -> GlassThisMacEvidence? {
        if keyMatches { return .hostKey }
        guard let address else { return nil }
        let wanted = normalized(address)
        guard !wanted.isEmpty, !["127.0.0.1", "::1", "localhost"].contains(wanted) else { return nil }
        return thisMacAddresses.contains(wanted) ? .address(wanted) : nil
    }
}
