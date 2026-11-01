import Testing
@testable import GlassConnectionUI

/// What the deck below an iPhone Duo's fold does with the keyboard (D93): it comes up on a fresh
/// fold only, stays away once put away, and unfolding puts it back as it was (UTM's rule).
@Suite("The deck below the fold")
struct GlassFoldDeckPolicyTests {
    @Test("a fresh fold brings the keyboard up, once")
    func freshFold() {
        var policy = GlassFoldDeckPolicy(start: .keyboard)
        #expect(policy.pose(laptop: true, keyboardShown: false) == .show)
        // Put away by the person while still stood up: the deck doesn't ask again.
        #expect(policy.pose(laptop: true, keyboardShown: false) == nil)
    }

    @Test("a keyboard already up is left as it is")
    func alreadyUp() {
        var policy = GlassFoldDeckPolicy(start: .keyboard)
        #expect(policy.pose(laptop: true, keyboardShown: true) == nil)
    }

    @Test("unfolding puts the keyboard back as it was before the fold")
    func unfoldRestores() {
        var policy = GlassFoldDeckPolicy(start: .keyboard)
        _ = policy.pose(laptop: true, keyboardShown: false)
        #expect(policy.pose(laptop: false, keyboardShown: true) == .hide, "it was away before the fold")

        var kept = GlassFoldDeckPolicy(start: .keyboard)
        _ = kept.pose(laptop: true, keyboardShown: true)
        #expect(kept.pose(laptop: false, keyboardShown: false) == .show, "it was up before the fold")
    }

    @Test("a desktop's fold brings up its panel: the keyboard goes")
    func panelFirst() {
        var policy = GlassFoldDeckPolicy(start: .panel)
        #expect(policy.pose(laptop: true, keyboardShown: true) == .hide)
        #expect(policy.pose(laptop: false, keyboardShown: false) == .show)
    }

    @Test("no fold, nothing to do; and each fold is fresh again")
    func noFold() {
        var policy = GlassFoldDeckPolicy(start: .keyboard)
        #expect(policy.pose(laptop: false, keyboardShown: false) == nil)
        _ = policy.pose(laptop: true, keyboardShown: false)
        _ = policy.pose(laptop: false, keyboardShown: false)
        #expect(policy.pose(laptop: true, keyboardShown: false) == .show)
    }
}
