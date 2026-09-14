import Testing
@testable import GlassConnectionUI

@Suite("Glass setting slider")
struct GlassSettingSliderTests {
    @Test func detentsSettleNearbyValuesAndLeaveOthersAlone() {
        let scale = GlassSettingSlider.Snapping(range: 0.5...2, detents: [1])
        #expect(scale.snapped(1.0) == 1)
        #expect(scale.snapped(0.99) == 1)
        #expect(scale.snapped(1.01) == 1)
        #expect(scale.snapped(0.98) == 0.98)
        #expect(scale.snapped(1.02) == 1.02)
        #expect(scale.snapped(0.5) == 0.5)
        #expect(scale.snapped(2) == 2)
    }

    @Test func detentsStayInsideTheRange() {
        let clamped = GlassSettingSlider.Snapping(range: 0.5...0.9, detents: [1])
        #expect(clamped.snapped(0.9) == 0.9)
    }

    @Test func percentageSettingsKeepTheirDefaultBehaviour() {
        let percentage = GlassSettingSlider.Snapping(range: 0...1, detents: [])
        #expect(percentage.snapped(0.37) == 0.37)
        #expect(percentage.snapped(0) == 0)
        #expect(percentage.snapped(1) == 1)
    }
}
