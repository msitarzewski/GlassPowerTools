//
//  DesktopNoticesTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/DesktopNoticesTests.swift` on 2026-09-27.
//  Adapted: `GlassDesktopUI` is `GlassDesktop` here, and the throwaway defaults suites are named for
//  this app. Every test and assertion is unchanged.
//

import Foundation
import Testing
@testable import GlassDesktop

@MainActor @Suite("Important session notices") struct DesktopNoticesTests {
    @Test func consentDenialOptOutAndDuplicateFailures() async {
        let key = "gpt-desktop-notice-test-\(UUID())"
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        var allowed = false
        var deliveries: [UUID] = []
        let notices = DesktopNotices(defaults: defaults, delivery: .init(authorize: { allowed }, failure: { id in
            deliveries.append(id); return true
        }))
        let attempt = UUID()
        await notices.connectionFailed(attempt: attempt)
        #expect(deliveries.isEmpty)
        await notices.setEnabled(true)
        #expect(!notices.isEnabled)
        #expect(notices.statusMessage != nil)
        allowed = true
        await notices.setEnabled(true)
        await notices.connectionFailed(attempt: attempt)
        await notices.connectionFailed(attempt: attempt)
        #expect(deliveries == [attempt])
        await notices.setEnabled(false)
        await notices.connectionFailed(attempt: UUID())
        #expect(deliveries == [attempt])
        #expect(!defaults.bool(forKey: DesktopNotices.preferenceKey))
    }

    @Test func revokedSystemPermissionDisablesFurtherNotices() async {
        let key = "gpt-desktop-notice-test-\(UUID())"
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        var count = 0
        let notices = DesktopNotices(defaults: defaults, delivery: .init(authorize: { true }, failure: { _ in
            count += 1; return false
        }))
        await notices.setEnabled(true)
        await notices.connectionFailed(attempt: UUID())
        await notices.connectionFailed(attempt: UUID())
        #expect(count == 1)
        #expect(!notices.isEnabled)
        #expect(notices.statusMessage != nil)
    }

    @Test func diagnosticDetailsAreBoundedAndSeparateFromFriendlyExplanation() {
        let detail = String(repeating: "x", count: 5000)
        let failure = DesktopFailurePresentation(hadDesktop: false, details: detail)
        #expect(failure.title == "Unable to Connect")
        #expect(failure.details.count == 4096)
        #expect(!failure.message.contains(detail))
    }
}
