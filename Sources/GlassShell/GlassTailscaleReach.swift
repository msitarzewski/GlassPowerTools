//
//  GlassTailscaleReach.swift
//  Glass Power Tools — GlassShell
//
//  A machine on a tailnet is reached only while this device is on that tailnet too (the owner, 2026-11-10: "We
//  should also recognize tailscale IP ranges and notify the user … when tailscale is required to be enabled before
//  connecting. This is different from the tailscale integration"). With Tailscale off here, a connection to a
//  tailnet address goes nowhere and waits out its timeout; it is said at once instead, with what to do.
//
//  **A tailnet address** (Tailscale's own reference, https://tailscale.com/docs/reference/reserved-ip-addresses and
//  https://tailscale.com/docs/concepts/ipv6): IPv4 from 100.64.0.0/10, the carrier-grade NAT block; IPv6 from
//  fd7a:115c:a1e0::/48; MagicDNS names end in `.ts.net`.
//
//  **This device on a tailnet:** Tailscale on Apple platforms is a VPN, a tunnel interface (`utun…`) holding the
//  device's tailnet address (seen on the owner's Mac, 2026-11-10: utun5 with a 100.x address and one in
//  fd7a:115c:a1e0::/48). Read with `getifaddrs`, which iOS and visionOS apps may call; no other app is asked.
//
//  100.64.0.0/10 is also carriers' NAT, so a 100.x host is not tailnet-only for certain: where this device's own
//  network is in that block (a carrier or satellite link handing it out), a 100.x host may be reached without
//  Tailscale, and nothing is said. fd7a:115c:a1e0::/48 and `.ts.net` are Tailscale's alone.
//

import Foundation

public enum GlassTailscaleReach {
    /// One address on one of this device's network interfaces.
    public struct InterfaceAddress: Equatable, Sendable {
        public let interface: String
        public let address: String
        public init(interface: String, address: String) {
            self.interface = interface
            self.address = address
        }
    }

    /// Whether `rawHost` is on a tailnet: a 100.64.0.0/10 or fd7a:115c:a1e0::/48 address, or a MagicDNS name.
    public static func isTailnetHost(_ rawHost: String) -> Bool {
        let host = normalized(rawHost)
        if host.hasSuffix(".ts.net") { return true }
        return isTailnetAddress(host)
    }

    /// Whether `address` (no brackets, no zone) is in one of Tailscale's ranges.
    static func isTailnetAddress(_ address: String) -> Bool {
        isTailnetIPv4(address) || isTailnetIPv6(address)
    }

    static func isTailnetIPv4(_ address: String) -> Bool {
        guard let octets = ipv4Octets(address) else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    static func isTailnetIPv6(_ address: String) -> Bool {
        guard address.contains(":") else { return false }
        var raw = in6_addr()
        guard inet_pton(AF_INET6, address, &raw) == 1 else { return false }
        let bytes = withUnsafeBytes(of: raw) { Array($0) }
        return bytes[0] == 0xfd && bytes[1] == 0x7a && bytes[2] == 0x11 && bytes[3] == 0x5c
            && bytes[4] == 0xa1 && bytes[5] == 0xe0
    }

    /// Whether this device is on a tailnet now: a tunnel interface holds a tailnet address.
    public static func isOnTailnet(_ interfaces: [InterfaceAddress] = interfaceAddresses()) -> Bool {
        interfaces.contains { $0.interface.hasPrefix("utun") && isTailnetAddress($0.address) }
    }

    /// Whether a connection to `rawHost` needs Tailscale on here and it is off: the host is on a tailnet, this device
    /// is not, and (for a 100.x host) this device's own network isn't carriers' NAT, which could reach it otherwise.
    public static func needsTailscale(_ rawHost: String,
                                      interfaces: [InterfaceAddress] = interfaceAddresses()) -> Bool {
        guard isTailnetHost(rawHost), !isOnTailnet(interfaces) else { return false }
        let host = normalized(rawHost)
        if isTailnetIPv4(host),
           interfaces.contains(where: { !$0.interface.hasPrefix("utun") && isTailnetIPv4($0.address) }) {
            return false
        }
        return true
    }

    /// A connection not made because the machine is on a tailnet and Tailscale is off on this device: thrown before
    /// dialling, so it is said at once rather than after the connect timeout.
    public struct Required: LocalizedError, Equatable, Sendable {
        public let machine: String
        public let host: String
        public init(machine: String, host: String) {
            self.machine = machine
            self.host = host
        }
        public var errorDescription: String? { GlassTailscaleReach.message(machine: machine, host: host) }
    }

    /// What to do, in the platform's words for this device.
    public static var advice: String {
        "Turn on Tailscale on this \(deviceName), then try again."
    }

    /// The whole message for a connection that needs Tailscale: the machine, where it is, and the fix.
    public static func message(machine: String, host: String) -> String {
        "\(machine) is on your tailnet (\(host)), and Tailscale is off on this \(deviceName). Turn it on, then try again."
    }

    /// "iPhone", "iPad", "Mac", "Apple Vision Pro": the local host's name without its "This".
    public static var deviceName: String {
        let name = GlassLocalHost.displayName
        return name.hasPrefix("This ") ? String(name.dropFirst(5)) : name
    }

    /// This device's interface addresses, IPv4 and IPv6, from `getifaddrs`.
    public static func interfaceAddresses() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [InterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let socket = entry.pointee.ifa_addr else { continue }
            let family = Int32(socket.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(socket, length, &text, socklen_t(text.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let name = String(cString: entry.pointee.ifa_name)
            result.append(InterfaceAddress(interface: name, address: normalized(address)))
        }
        return result
    }

    /// Lowercased, without brackets or an IPv6 zone (`fe80::1%en0`).
    static func normalized(_ rawHost: String) -> String {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        if host.hasSuffix(".") { host.removeLast() }
        return host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
    }

    static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let values = parts.compactMap { Int($0) }
        guard parts.count == 4, values.count == 4, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return values
    }
}
