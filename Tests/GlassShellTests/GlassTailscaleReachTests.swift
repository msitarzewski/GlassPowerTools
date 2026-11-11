//
//  GlassTailscaleReachTests.swift
//  Glass Power Tools — GlassShellTests
//
//  A machine on a tailnet needs Tailscale on this device (the owner, 2026-11-10). What must hold: Tailscale's
//  ranges and MagicDNS names are recognised and nothing else is; this device counts as on a tailnet only by a
//  tunnel holding a tailnet address; a 100.x host is not said to need Tailscale where this device's own network is
//  carriers' NAT; and a Tailscale IPv6 host is not taken for the local network.
//

import Foundation
import Testing
@testable import GlassShell

@Suite("A machine on a tailnet needs Tailscale on here")
struct GlassTailscaleReachTests {
    private typealias Address = GlassTailscaleReach.InterfaceAddress

    /// Tailscale off: Wi-Fi and the cellular link, as a phone has.
    private let off = [Address(interface: "en0", address: "192.168.1.20"),
                       Address(interface: "en0", address: "fe80::1c2b:3a4d:5e6f:7081"),
                       Address(interface: "pdp_ip0", address: "10.44.12.9")]
    /// Tailscale on: the same, and its tunnel, as the owner's Mac showed (utun with both of its ranges).
    private var on: [Address] {
        off + [Address(interface: "utun5", address: "100.92.10.11"),
               Address(interface: "utun5", address: "fd7a:115c:a1e0::5f01:2a0b")]
    }

    @Test("its ranges and names: 100.64.0.0/10, fd7a:115c:a1e0::/48, .ts.net")
    func tailnetHosts() {
        for host in ["100.64.0.1", "100.92.10.11", "100.127.255.254", "100.100.100.100",
                     "fd7a:115c:a1e0::1", "[fd7a:115c:a1e0:ab12::7]", "FD7A:115C:A1E0::9%utun5",
                     "mac.tail1234.ts.net", "Mac.Tail1234.TS.NET."] {
            #expect(GlassTailscaleReach.isTailnetHost(host), "\(host)")
        }
        for host in ["100.63.255.255", "100.128.0.1", "10.0.0.5", "192.168.1.20", "fd7a:115c:a1e1::1",
                     "fd12::20", "example.com", "ts.net.example.com", "100.92.10", "not-an-address", ""] {
            #expect(!GlassTailscaleReach.isTailnetHost(host), "\(host)")
        }
    }

    @Test("on a tailnet: a tunnel holding a tailnet address, and nothing else")
    func onTailnet() {
        #expect(GlassTailscaleReach.isOnTailnet(on))
        #expect(!GlassTailscaleReach.isOnTailnet(off))
        #expect(GlassTailscaleReach.isOnTailnet(off + [Address(interface: "utun3", address: "fd7a:115c:a1e0::2")]),
                "IPv6 alone is enough")
        #expect(!GlassTailscaleReach.isOnTailnet(off + [Address(interface: "utun2", address: "10.2.0.2")]),
                "another VPN's tunnel is not Tailscale")
        #expect(!GlassTailscaleReach.isOnTailnet(off + [Address(interface: "pdp_ip0", address: "100.70.1.2")]),
                "a carrier's NAT address on the cellular link is not Tailscale")
    }

    @Test("needs Tailscale: a tailnet host with Tailscale off here, and only then")
    func needsTailscale() {
        #expect(GlassTailscaleReach.needsTailscale("100.92.10.12", interfaces: off))
        #expect(GlassTailscaleReach.needsTailscale("fd7a:115c:a1e0::5f01:2a0c", interfaces: off))
        #expect(GlassTailscaleReach.needsTailscale("mac.tail1234.ts.net", interfaces: off))
        #expect(!GlassTailscaleReach.needsTailscale("100.92.10.12", interfaces: on))
        #expect(!GlassTailscaleReach.needsTailscale("mac.tail1234.ts.net", interfaces: on))
        #expect(!GlassTailscaleReach.needsTailscale("192.168.1.30", interfaces: off))
        #expect(!GlassTailscaleReach.needsTailscale("example.com", interfaces: off))
    }

    @Test("a 100.x host is not said to need Tailscale where this device's own network is carriers' NAT")
    func carrierNAT() {
        let carrier = off + [Address(interface: "pdp_ip0", address: "100.70.1.2")]
        #expect(!GlassTailscaleReach.needsTailscale("100.70.1.1", interfaces: carrier))
        #expect(GlassTailscaleReach.needsTailscale("fd7a:115c:a1e0::1", interfaces: carrier), "IPv6 is Tailscale's alone")
        #expect(GlassTailscaleReach.needsTailscale("mac.tail1234.ts.net", interfaces: carrier), ".ts.net is Tailscale's")
    }

    @Test("this device's own addresses are read, and Tailscale's verdict on them is consistent")
    func readsThisDevice() {
        let addresses = GlassTailscaleReach.interfaceAddresses()
        #expect(addresses.contains { $0.interface.hasPrefix("lo") }, "the loopback interface is always there")
        #expect(addresses.allSatisfy { !$0.address.contains("%") }, "zones are taken off")
        #expect(GlassTailscaleReach.isOnTailnet(addresses)
                == addresses.contains { $0.interface.hasPrefix("utun") && GlassTailscaleReach.isTailnetAddress($0.address) })
    }

    @Test("the message names the machine, where it is, and the fix")
    @MainActor func message() {
        let text = GlassTailscaleReach.message(machine: "studio", host: "100.92.10.12")
        #expect(text.contains("studio is on your tailnet (100.92.10.12)"))
        #expect(text.contains("Tailscale is off on this"))
        #expect(text.hasSuffix("Turn it on, then try again."))
    }

    @Test("a Tailscale IPv6 host is not the local network; other unique-local addresses still are")
    func notLocalNetwork() {
        #expect(!GlassLocalNetworkAccess.isLikelyLocalHost("fd7a:115c:a1e0::5f01:2a0c"))
        #expect(!GlassLocalNetworkAccess.isLikelyLocalHost("[fd7a:115c:a1e0::1]"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("fd12::20"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("fda6:7be9:d6cb:1::5"))
    }
}
