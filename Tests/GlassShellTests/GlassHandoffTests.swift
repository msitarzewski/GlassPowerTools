import Foundation
import Testing
@testable import GlassShell

/// Handoff (D72): what a session offers other devices, and what continuing it reads back.
@Suite("Handoff")
struct GlassHandoffTests {
    @Test("the activity names the service and nothing else; another kind of activity names none")
    func activity() {
        let endpoint = UUID()
        let activity = NSUserActivity(activityType: GlassHandoff.activityType)
        GlassHandoff.describe(activity, endpoint: endpoint, title: "alpha")
        #expect(GlassHandoff.endpoint(from: activity) == endpoint)
        #expect(activity.title == "alpha")
        #expect(activity.isEligibleForHandoff && !activity.isEligibleForSearch)
        #expect(Set((activity.userInfo ?? [:]).keys.compactMap { $0 as? String }) == ["endpoint"],
                "an address, a user or a credential has no place in what other devices are offered")

        let other = NSUserActivity(activityType: "com.example.other")
        other.userInfo = ["endpoint": endpoint.uuidString]
        #expect(GlassHandoff.endpoint(from: other) == nil)
    }

    @Test("a terminal in tmux names its session; one outside tmux names none")
    func tmux() {
        let inTmux = NSUserActivity(activityType: GlassHandoff.activityType)
        GlassHandoff.describe(inTmux, endpoint: UUID(), title: "alpha", tmuxSession: "glass-3")
        #expect(GlassHandoff.tmuxSession(from: inTmux) == "glass-3")

        let plain = NSUserActivity(activityType: GlassHandoff.activityType)
        GlassHandoff.describe(plain, endpoint: UUID(), title: "alpha", tmuxSession: nil)
        #expect(GlassHandoff.tmuxSession(from: plain) == nil)
        #expect((plain.userInfo ?? [:]).count == 1)
    }
}
