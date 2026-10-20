import Foundation
import Testing
@testable import GlassShell

/// D86: how this Mac recognises a library machine as itself — by its SSH host key, which proves it
/// (`SSHHostKeyIdentity`), or by an address of its own, which is offered rather than taken.
@Suite("This Mac, recognised")
struct GlassThisMacTests {
    @Test("addresses compare without case, brackets, a zone or a trailing dot")
    func normalising() {
        #expect(GlassThisMac.normalized(" Alpha.Local. ") == "alpha.local")
        #expect(GlassThisMac.normalized("[fe80::1%en0]") == "fe80::1")
    }

    @Test("a pinned key of this Mac's is proof; an address of this Mac's is a hint; loopback is neither")
    func evidence() {
        let mine: Set<String> = ["192.0.2.10", "alpha.local"]
        #expect(GlassThisMac.evidence(address: "198.51.100.7", keyMatches: true, thisMacAddresses: mine) == .hostKey)
        #expect(GlassThisMac.evidence(address: "Alpha.local", keyMatches: false, thisMacAddresses: mine) == .address("alpha.local"))
        #expect(GlassThisMac.evidence(address: "198.51.100.7", keyMatches: false, thisMacAddresses: mine) == nil)
        #expect(GlassThisMac.evidence(address: "127.0.0.1", keyMatches: false, thisMacAddresses: ["127.0.0.1"]) == nil)
        #expect(GlassThisMac.evidence(address: nil, keyMatches: false, thisMacAddresses: mine) == nil)
    }

    #if os(macOS)
    @Test("this Mac has addresses of its own")
    func ownAddresses() {
        let addresses = GlassThisMac.addresses()
        #expect(!addresses.isEmpty)
        #expect(!addresses.contains("127.0.0.1"))
    }
    #endif
}
