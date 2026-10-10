import Testing
import Foundation
@testable import GlassEditorUI

/// Rule 64 for the editor: its UIKit text view is built on the next main-queue turn, never inside
/// the SwiftUI update that asked for it (`PlatformEditor.makeUIView`). The representable itself is
/// UIKit and cannot run here; the scheduling it relies on can.
@Suite("The editor's view is built after the update that asks for it")
@MainActor
struct NextTurnBuildTests {
    final class Built {}

    /// Lets the main queue run everything already queued on it, then returns.
    private func nextTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func nothingIsBuiltInsideTheCallThatAsks() async {
        let build = GlassEditorNextTurnBuild<Built>()
        var calls = 0
        build.schedule { calls += 1; return Built() }
        #expect(calls == 0, "built inside the update — the headset's crash shape")
        #expect(build.built == nil)

        await nextTurn()
        #expect(calls == 1)
        #expect(build.built != nil)
    }

    @Test func askingAgainBuildsOnce() async {
        // SwiftUI may ask more than once before the first build has run; one view, one engine.
        let build = GlassEditorNextTurnBuild<Built>()
        var calls = 0
        build.schedule { calls += 1; return Built() }
        build.schedule { calls += 1; return Built() }
        await nextTurn()
        build.schedule { calls += 1; return Built() }
        await nextTurn()
        #expect(calls == 1)
    }

    @Test func aHostThatWentAwayGetsNothing() async {
        // The window closed before the turn came round: `make` says so, and nothing is kept.
        let build = GlassEditorNextTurnBuild<Built>()
        build.schedule { nil }
        await nextTurn()
        #expect(build.built == nil)
    }
}
