#if os(macOS)
import Testing
@testable import GlassTerminal

/// The busy tab's light (2026-10-12: the light sweep, in place of the wave).
@Suite("A busy tab's light sweep")
struct MacTerminalActivityShimmerTests {
    @Test("each pass starts wholly before the row, ends wholly past it, moves only forward, then rests")
    func passes() {
        let width = 200.0, band = 90.0
        let start = MacTerminalActivityShimmer.bandCenter(at: 0, width: width, band: band)
        #expect(start == -band / 2, "the band's trailing edge at the row's start")
        let nearEnd = MacTerminalActivityShimmer.bandCenter(at: MacTerminalActivityShimmer.sweep - 0.0001, width: width, band: band)
        #expect((nearEnd ?? 0) > width + band / 2 - 0.5, "the band's leading edge past the row's end")
        var last = -Double.infinity
        for step in stride(from: 0.0, to: MacTerminalActivityShimmer.sweep, by: 0.02) {
            let center = MacTerminalActivityShimmer.bandCenter(at: step, width: width, band: band) ?? .nan
            #expect(center >= last, "at \(step)")
            last = center
        }
        #expect(MacTerminalActivityShimmer.bandCenter(at: MacTerminalActivityShimmer.sweep + 0.1, width: width, band: band) == nil,
                "resting between passes")
        #expect(MacTerminalActivityShimmer.bandCenter(at: MacTerminalActivityShimmer.period, width: width, band: band) == -band / 2,
                "and the next pass starts as the first did")
    }
}
#endif
