#if os(macOS)
import AppKit
import Foundation
import GlassLayers
import GlassTerminalEmulator
import SwiftUI
import Testing
@testable import GlassTerminal

/// Scale Text on a Mac's own terminal (2026-10-20, the owner: "Why is this? 'A terminal on the Mac
/// itself always changes its rows and columns with its window.'"): the local pane never applied the
/// window's When Resized, so a local tab ignored Scale. A real pane, a real shell, asked its size.
@MainActor
@Suite("Scale Text on a local terminal", .serialized)
struct MacLocalPaneScaleTests {
    private func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("under Scale a smaller window keeps the shell's rows and columns")
    func smallerWindowKeepsTheShellsGrid() async throws {
        let suite = "MacLocalPaneScale.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        var window = GlassWindowOverrides()
        window[TerminalWindowSettings.whenResized] = TerminalResizeBehavior.scale.rawValue

        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        let pane = MacLocalTerminalPaneView(
            runtime: runtime, recorder: SessionRecorder(), workspaceID: UUID(),
            shellOverride: "/bin/sh", directoryOverride: NSTemporaryDirectory(),
            isFocused: true, showsPaneChrome: false, findRequest: .none,
            claimStartupCommand: { nil }, onFocus: {}, onDisconnect: {}, onProcessStatusChange: { _ in },
            hostModel: runtime.model, processState: runtime.processState)
            .environment(settings)
            .glassWindowOverrides(window)
        let hosting = NSHostingView(rootView: pane)
        let host = NSWindow()
        host.isReleasedWhenClosed = false
        host.setContentSize(NSSize(width: 900, height: 560))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        host.contentView = hosting
        defer { host.contentView = nil }
        hosting.layoutSubtreeIfNeeded()

        #expect(await waitFor(seconds: 10) { runtime.processState.isRunning }, "the shell never started")
        let scaling = await waitFor(seconds: 5) { runtime.model.scaledGrid != nil }
        #expect(scaling, "the window scales, but the local terminal never started keeping its grid")
        let kept = try #require(runtime.model.scaledGrid)

        func shellSize() async -> String? {
            let marker = "SIZE\(Int.random(in: 1000...9999))"
            _ = runtime.processState.sendCommand("echo \(marker) $(stty size)")
            var found: String?
            _ = await waitFor(seconds: 5) {
                found = runtime.model.getVisibleText(lastNLines: 8).last { $0.hasPrefix(marker) }
                return found != nil
            }
            return found.map { String($0.dropFirst(marker.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        let before = await shellSize()
        #expect(before == "\(kept.rows) \(kept.columns)", "the shell has the kept grid: \(before ?? "nothing")")

        host.setContentSize(NSSize(width: 450, height: 280))
        hosting.frame = NSRect(x: 0, y: 0, width: 450, height: 280)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let after = await shellSize()
        #expect(after == before, "half the window, and the shell was told \(after ?? "nothing") instead of \(before ?? "")")
    }
}
#endif
