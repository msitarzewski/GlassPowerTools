//
//  DesktopGraphicsModeTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  B-F32: a Remote Desktop service chooses which pictures its server is asked for — Automatic, H.264
//  4:2:0 only, or no H.264 — the way out when a server draws badly with H.264 4:4:4 (B-X6). What must
//  hold: the choice reaches the connection, a record saved before it existed reads as Automatic, and
//  Screen Sharing never carries one.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassRDPTransport
@testable import GlassDesktop

// That the choice reaches the connection is in `SessionRegressionTests.swift` ("A desktop's graphics
// choice reaches the connection"), beside the session fixture it needs.
@Suite("A desktop's graphics choice")
struct DesktopGraphicsModeTests {
    @Test("a record written before the choice existed, or by a later build, reads as Automatic")
    func olderAndNewerRecords() throws {
        var saved = DesktopConnection(name: "Server", host: "server.example", username: "alice")
        saved.graphicsMode = .h264
        let encoded = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode(DesktopConnection.self, from: encoded).graphicsMode == .h264)

        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["graphicsMode"] = nil
        let older = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DesktopConnection.self, from: older).graphicsMode == .automatic)

        object["graphicsMode"] = "a mode from a later build"
        let newer = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DesktopConnection.self, from: newer).graphicsMode == .automatic,
                "an unknown mode failed the whole record")
    }

    @Test("Screen Sharing carries no graphics choice")
    func screenSharingHasNone() throws {
        var vnc = DesktopConnection(name: "Mac", host: "mac.example", username: "", protocol: .vnc)
        vnc.port = 5900
        vnc.graphicsMode = .withoutH264
        #expect(try vnc.validated().graphicsMode == .automatic)
    }
}
