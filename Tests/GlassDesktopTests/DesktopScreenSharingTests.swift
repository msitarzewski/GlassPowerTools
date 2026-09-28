//
//  DesktopScreenSharingTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Open in Screen Sharing hands over the endpoint and nothing else (glassDT's rule, kept).
//

import Foundation
import Testing
@testable import GlassDesktop

@Suite("Screen Sharing gets the endpoint only")
struct DesktopScreenSharingTests {

    @Test func aVNCDesktopBecomesAVNCLinkWithItsPort() throws {
        let connection = DesktopConnection(name: "alpha", host: "192.0.2.10", port: 5901,
                                           username: "casey", protocol: .vnc)
        let url = try #require(DesktopScreenSharing.url(for: connection))
        #expect(url.absoluteString == "vnc://192.0.2.10:5901")
        #expect(url.user == nil && url.password == nil, "no account or secret travels in the link")
    }

    @Test func anIPv6HostIsBracketed() throws {
        let connection = DesktopConnection(name: "alpha", host: "2001:db8::10", port: 5900, protocol: .vnc)
        #expect(DesktopScreenSharing.url(for: connection)?.absoluteString == "vnc://[2001:db8::10]:5900")
    }

    @Test func anRDPDesktopIsNotOffered() {
        let connection = DesktopConnection(name: "alpha", host: "192.0.2.10", protocol: .rdp)
        #expect(DesktopScreenSharing.url(for: connection) == nil)
    }
}
