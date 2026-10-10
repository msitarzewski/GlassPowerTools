//
//  GlassConnectionsIdleTests.swift
//  Glass Power Tools — GlassShellTests
//
//  When the headset's Connections window shrinks into its orb, and what keeps it at full size
//  (W29). The rule is pure, so it is tested here on its own; the window feeding it is driven on
//  the visionOS simulator by `GlassConnectionsOrbUITests`.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

@Suite("Connections shrinks into its orb when idle")
struct GlassConnectionsIdleTests {
    private let start = ContinuousClock.now

    /// Another window open and nothing over Connections: the state in which it may shrink.
    private var free: GlassConnectionsIdleState { GlassConnectionsIdleState(otherWindows: 1) }

    // MARK: When

    @Test func itShrinksOnceIdleForTheWholeInterval() {
        var clock = GlassConnectionsIdleClock(now: start)
        #expect(clock.decide(.twoMinutes, free, now: start + .seconds(119)) == .wait(.seconds(1)))
        #expect(clock.decide(.twoMinutes, free, now: start + .seconds(120)) == .shrink)
        #expect(clock.decide(.twoMinutes, free, now: start + .seconds(600)) == .shrink)
    }

    @Test func everyTouchStartsTheIntervalAgain() {
        var clock = GlassConnectionsIdleClock(now: start)
        clock.interaction(at: start + .seconds(100))
        #expect(clock.decide(.twoMinutes, free, now: start + .seconds(130)) == .wait(.seconds(90)),
                "the clock counted from the window's opening, not from its last use")
        #expect(clock.decide(.twoMinutes, free, now: start + .seconds(220)) == .shrink)
    }

    @Test func anOlderReportNeverWindsTheClockBack() {
        var clock = GlassConnectionsIdleClock(now: start)
        clock.interaction(at: start + .seconds(100))
        clock.interaction(at: start + .seconds(10))
        #expect(clock.idleSince == start + .seconds(100))
    }

    @Test func neverStopsWatching() {
        var clock = GlassConnectionsIdleClock(now: start)
        #expect(clock.decide(.never, free, now: start + .seconds(86_400)) == .off)
    }

    // MARK: What holds it

    @Test func theOnlyWindowStaysPut() {
        var clock = GlassConnectionsIdleClock(now: start)
        let alone = GlassConnectionsIdleState(otherWindows: 0)
        #expect(clock.decide(.oneMinute, alone, now: start + .seconds(3600)) == .held(.onlyWindow, recheck: .seconds(60)))
    }

    @Test(arguments: [
        (GlassConnectionsIdleState(otherWindows: 1, isPresenting: true), GlassConnectionsIdleHold.presenting),
        (GlassConnectionsIdleState(otherWindows: 1, isEditingText: true), .editingText),
        (GlassConnectionsIdleState(otherWindows: 1, isTouching: true), .touching),
        (GlassConnectionsIdleState(otherWindows: 1, isDragging: true), .dragging),
        (GlassConnectionsIdleState(isOnScreen: false, otherWindows: 1), .notOnScreen),
    ])
    func eachHoldKeepsItFullSize(state: GlassConnectionsIdleState, hold: GlassConnectionsIdleHold) {
        var clock = GlassConnectionsIdleClock(now: start)
        #expect(clock.decide(.oneMinute, state, now: start + .seconds(3600)) == .held(hold, recheck: .seconds(60)))
    }

    @Test func aConnectionStillAnsweringHoldsIt() {
        var clock = GlassConnectionsIdleClock(now: start)
        let connecting = GlassConnectionsIdleState(otherWindows: 1, connectingSince: start + .seconds(30))
        #expect(clock.decide(.oneMinute, connecting, now: start + .seconds(90)) == .held(.connecting, recheck: .seconds(60)))
    }

    /// A capability whose report never comes must not keep Connections at full size all day.
    @Test func aConnectionThatNeverAnswersStopsHoldingIt() {
        var clock = GlassConnectionsIdleClock(now: start)
        let stuck = GlassConnectionsIdleState(otherWindows: 1, connectingSince: start)
        let limit = GlassConnectionsIdleClock.connectingLimit
        #expect(clock.decide(.oneMinute, stuck, now: start + limit - .seconds(1)) == .held(.connecting, recheck: .seconds(60)))
        var later = GlassConnectionsIdleClock(now: start)
        #expect(later.decide(.oneMinute, stuck, now: start + limit) == .shrink)
    }

    /// Closing a sheet after five minutes must not shrink the window under the person's hand:
    /// a hold starts the interval again.
    @Test func afterAHoldEndsItWaitsAWholeIntervalAgain() {
        var clock = GlassConnectionsIdleClock(now: start)
        let sheet = GlassConnectionsIdleState(otherWindows: 1, isPresenting: true)
        _ = clock.decide(.twoMinutes, sheet, now: start + .seconds(300))
        #expect(clock.decide(.twoMinutes, free, now: start + .seconds(301)) == .wait(.seconds(119)))
        #expect(clock.decide(.twoMinutes, free, now: start + .seconds(420)) == .shrink)
    }

    /// The order the reasons are reported in: not on screen, then alone, then what is open over it.
    @Test func theFirstHoldIsTheOneReported() {
        let everything = GlassConnectionsIdleState(isOnScreen: false, otherWindows: 0, isPresenting: true,
                                                   isEditingText: true, isTouching: true, isDragging: true,
                                                   connectingSince: start)
        #expect(everything.hold(now: start) == .notOnScreen)
        var alone = everything
        alone.isOnScreen = true
        #expect(alone.hold(now: start) == .onlyWindow)
        #expect(free.hold(now: start) == nil)
    }

    // MARK: The setting

    @Test func theChoicesAreNeverAndOneTwoFiveTenMinutes() {
        #expect(GlassConnectionsIdleShrink.allCases.map(\.title) == ["Never", "1 Minute", "2 Minutes", "5 Minutes", "10 Minutes"])
        #expect(GlassConnectionsIdleShrink.allCases.map(\.interval) == [nil, .seconds(60), .seconds(120), .seconds(300), .seconds(600)])
    }

    @Test func twoMinutesUntilChosenOtherwise() {
        #expect(GlassConnectionsIdleShrink.standard == .twoMinutes)
        #expect(GlassConnectionsIdleShrink(storedSeconds: nil) == .twoMinutes, "an unset setting reads as Never")
    }

    @Test func aStoredChoiceReadsBack() {
        for choice in GlassConnectionsIdleShrink.allCases {
            #expect(GlassConnectionsIdleShrink(storedSeconds: choice.rawValue) == choice)
        }
        #expect(GlassConnectionsIdleShrink(storedSeconds: 0) == .never, "Never, chosen, reads as the default")
    }

    /// A value no build offered never switches the feature off.
    @Test func anUnknownStoredValueReadsAsTheStandard() {
        #expect(GlassConnectionsIdleShrink(storedSeconds: 45) == .standard)
        #expect(GlassConnectionsIdleShrink(storedSeconds: -1) == .standard)
    }

    @Test func theSettingIsKeptUnderItsOwnKey() {
        #expect(GlassConnectionsIdleShrink.settingKey == "com.glasspowertools.library.idleShrinkSeconds")
    }
}

// MARK: - A connection still answering

@MainActor
private final class HeldReportCapability: GlassCapability {
    let kind: HostServiceKind = .ssh
    let displayName = "Held"
    let symbolName = "circle"
    var pending: [@MainActor (GlassCapabilityOutcome) -> Void] = []

    func open(service: HostServiceLink, host: HostProfile,
              report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { pending.append(report) }
}

@MainActor
@Suite("The library knows when a connection it started is still answering")
struct GlassConnectingSinceTests {
    @Test(arguments: [GlassCapabilityOutcome.connected, .failed("refused"), .dismissed])
    func aConnectionIsConnectingUntilItsCapabilityReports(outcome: GlassCapabilityOutcome) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectingSince-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let capability = HeldReportCapability()
        model.registry.register(capability)
        await model.load()
        // A saved machine. The catalog is written with file protection, so this test needs the
        // Mac's screen unlocked (rule 56).
        _ = try await model.adoptService(kind: .ssh, hostName: "alpha", address: "192.0.2.10",
                                         serviceName: "Terminal on alpha")
        let alpha = try #require(model.hosts.first { $0.displayName == "alpha" })
        #expect(model.connectingSince == nil)

        let before = ContinuousClock.now
        model.connect(hostID: alpha.id)
        let since = try #require(model.connectingSince, "Connect did not count as connecting")
        #expect(since >= before)
        #expect(capability.pending.count == 1)

        capability.pending[0](outcome)
        #expect(model.connectingSince == nil, "\(outcome) left the library connecting")
        // A second report of the same attempt changes nothing.
        capability.pending[0](outcome)
        #expect(model.connectingSince == nil)
    }
}
