import Foundation
import Testing
@testable import GlassLayers

@Suite("A UI test run keeps its settings in its own suite")
struct GlassUITestRunTests {
    @Test("outside a UI test run there is no test suite, so the person's own store is used")
    func noSuiteOutsideATestRun() {
        // `swift test` runs without `--ui-testing <uuid>`.
        #expect(GlassUITestRun.defaults == nil)
    }

    @Test("a run's suite is named for the app and the run, so two runs never share one")
    func suiteNamePerRun() {
        let first = UUID(), second = UUID()
        #expect(GlassUITestRun.suiteName(for: first) == "\(GlassAppIdentity.appGroup).uitests.\(first.uuidString)")
        #expect(GlassUITestRun.suiteName(for: first) != GlassUITestRun.suiteName(for: second))
    }
}
