#if os(macOS)
#if os(macOS)
import AppKit
import Darwin
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import GlassTerminalEmulator
import SwiftUI
import Testing
import UniformTypeIdentifiers
import GlassLayers
@testable import GlassTerminal

@MainActor
private final class IncomingPromiseTestDelegate: NSObject, NSFilePromiseProviderDelegate {
    var requestedWrite = false
    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType type: String) -> String {
        "Photo.png"
    }
    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        requestedWrite = true
        completionHandler(CocoaError(.userCancelled))
    }
}

@Suite(.serialized)
struct MacWorkspaceTests {
    @Test @MainActor func overviewCollapsesNativeSidebarEvenAfterInitialOpening() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let split = NSSplitViewController()
        let sidebarController = NSViewController()
        sidebarController.view = NSView()
        let detailController = NSViewController()
        detailController.view = NSView()
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarController)
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: detailController))
        window.contentViewController = split
        let coordinator = MacTerminalWindowReader.Coordinator()
        coordinator.configureInitialSidebar(in: window, enabled: true)
        #expect(!sidebar.isCollapsed)
        let overviewFirst = MacTerminalWindowReader.Coordinator()
        overviewFirst.configureInitialSidebar(in: window, enabled: false, overviewPresented: true)
        #expect(sidebar.isCollapsed)
        overviewFirst.configureInitialSidebar(in: window, enabled: true)
        #expect(sidebar.isCollapsed, "Returning from overview must not replay startup sidebar opening.")
        sidebar.isCollapsed = false
        coordinator.configureInitialSidebar(in: window, enabled: false, overviewPresented: true)
        #expect(sidebar.isCollapsed)
        sidebar.isCollapsed = false // Native restoration must not reopen it in overview.
        coordinator.configureInitialSidebar(in: window, enabled: false, overviewPresented: true)
        #expect(sidebar.isCollapsed)
        coordinator.configureInitialSidebar(in: window, enabled: true, overviewPresented: false)
        sidebar.isCollapsed = false // Tabs' saved visibility can take ownership again.
        coordinator.configureInitialSidebar(in: window, enabled: true)
        #expect(!sidebar.isCollapsed)
    }

    @Test func overviewIdlePolicyDefersToControlsAndRestartsOnInteraction() {
        let start = ContinuousClock.now
        var policy = MacOverviewIdlePolicy()
        policy.interact(at: start)
        #expect(!policy.shouldHide(at: start.advanced(by: .seconds(2)), canHide: true))
        #expect(policy.shouldHide(at: start.advanced(by: .seconds(3)), canHide: true))
        #expect(!policy.shouldHide(at: start.advanced(by: .seconds(8)), canHide: false))
        policy.interact(at: start.advanced(by: .seconds(8)))
        #expect(!policy.shouldHide(at: start.advanced(by: .seconds(9)), canHide: true))
    }

    @Test func previewTitleColorPrioritizesErrorsAndTransitions() {
        #expect(MacTerminalPreviewStatus.color(for: ["Running", "Error: Connection lost"]) == .red)
        #expect(MacTerminalPreviewStatus.color(for: ["Connected", "Reconnecting..."]) == .orange)
        #expect(MacTerminalPreviewStatus.color(for: ["Running"]) == .green)
        #expect(MacTerminalPreviewStatus.color(for: ["Disconnected", "Exited"]) == .secondary)
    }

    @Test func workgroupPresentationPreferencesRoundTripAndLegacyDefaults() throws {
        var preset = LayoutPreset(name: "Monitor", sessionIntents: [.init(kind: .local)])
        preset.openingView = .carousel
        preset.autoFocusOnActivity = true
        preset.gridCardWidth = 460
        let data = try JSONEncoder().encode(preset)
        #expect(try JSONDecoder().decode(LayoutPreset.self, from: data) == preset)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "openingView")
        legacy.removeValue(forKey: "autoFocusOnActivity")
        legacy.removeValue(forKey: "gridCardWidth")
        let restored = try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.openingView == .tabs)
        #expect(!restored.autoFocusOnActivity)
        #expect(restored.gridCardWidth == nil)
        let copy = WorkgroupEditorContext.duplicate(preset)
        #expect(copy.openingView == .carousel)
        #expect(copy.autoFocusOnActivity)
        #expect(copy.gridCardWidth == 460)
    }

    @Test func activityFollowingIgnoresHistoryAndYieldsToManualNavigation() {
        let first = UUID(), second = UUID()
        let start = ContinuousClock.now
        var activity = MacTerminalActivitySelection()
        activity.baseline([first: start, second: start])
        #expect(activity.candidate(in: [first: start, second: start], now: start) == nil)
        let next = start.advanced(by: .seconds(1))
        #expect(activity.candidate(in: [first: start, second: next], now: next) == second)
        #expect(activity.candidate(in: [first: start, second: next], now: next) == nil)
        activity.didNavigate(at: next)
        let duringGrace = start.advanced(by: .seconds(2))
        #expect(activity.candidate(in: [first: duringGrace, second: next], now: duringGrace) == nil)
        let afterGrace = start.advanced(by: .seconds(5))
        #expect(activity.candidate(in: [first: duringGrace, second: next], now: afterGrace) == nil)
        #expect(activity.candidate(in: [first: afterGrace, second: next], now: afterGrace) == first)
        // Removed tabs cannot attract attention from stale samples.
        #expect(activity.candidate(in: [second: next], now: afterGrace) == nil)
    }

    @Test func overviewNavigationClampsAndRepairsMissingSelection() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        #expect(MacTerminalOverviewNavigation.moved(nil, by: 0, in: ids) == ids[0])
        #expect(MacTerminalOverviewNavigation.moved(ids[0], by: -1, in: ids) == ids[0])
        #expect(MacTerminalOverviewNavigation.moved(ids[0], by: 2, in: ids) == ids[2])
        #expect(MacTerminalOverviewNavigation.moved(ids[3], by: 1, in: ids) == ids[3])
        #expect(MacTerminalOverviewNavigation.moved(UUID(), by: 0, in: ids) == ids[0])
        #expect(MacTerminalOverviewNavigation.moved(nil, by: 1, in: []) == nil)
    }

    @Test @MainActor func previewDoesNotCreateRuntimeOrAlterWorkspace() throws {
        let suite = "overview-no-side-effects-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MacWorkspaceController(workspaceID: UUID(), defaults: defaults)
        let before = controller.state
        let pane = try #require(before.root?.panes.first)
        #expect(controller.previewModel(for: pane.id) == nil)
        #expect(controller.previewStatus(for: pane.id) == "Not running")
        #expect(controller.localRuntimesByPaneID.isEmpty)
        #expect(controller.sessionsByPaneID.isEmpty)
        #expect(controller.state == before)
        #expect(SwiftTermHostModel().previewImage() == nil)
    }

    @Test @MainActor func offscreenPreviewIsBoundedLiveAndDoesNotSendInputOrResize() async throws {
        let model = SwiftTermHostModel()
        var inputs = 0
        var resizes = 0
        let host = SwiftTermHostView(model: model,
            theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1),
                                 background: (0, 0, 0, 0), cursor: (1, 1, 1)),
            runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100),
            allowsFocusOwnership: false,
            onSendData: { _ in inputs += 1 }, onResize: { _, _ in resizes += 1 })
        host.prepareOffscreen(columns: 100, rows: 30)
        defer { model.releaseRenderer() }
        model.ingest(data: Data("PREVIEW ONE\r\n".utf8), nonce: 1)
        #expect(await waitForCondition(seconds: 2) { model.getVisibleText(lastNLines: 30).joined().contains("PREVIEW ONE") })
        let resizeCount = resizes
        let inputCount = inputs
        let first = try #require(model.previewImage(maxPixelWidth: 320))
        #expect(first.size.width <= 320)
        #expect(first.size.height <= 640)
        let bitmap = try #require(first.representations.first as? NSBitmapImageRep)
        let emptyPixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1))
        #expect(emptyPixel.alphaComponent == 0, "Previews must preserve a transparent terminal background.")
        // Preparing again must reuse the engine and preserve its original grid.
        host.prepareOffscreen(columns: 40, rows: 10)
        model.ingest(data: Data("\u{1b}[31mPREVIEW TWO\u{1b}[0m\r\n".utf8), nonce: 2)
        #expect(await waitForCondition(seconds: 2) { model.getVisibleText(lastNLines: 30).joined().contains("PREVIEW TWO") })
        let second = try #require(model.previewImage(maxPixelWidth: 320))
        #expect(first.tiffRepresentation != second.tiffRepresentation)
        #expect(first.size == second.size)
        #expect(resizes == resizeCount)
        #expect(inputs == inputCount)
        #expect(!model.allowsFocusOwnership)
        #expect(!model.rendererDiagnostics.isWindowAttached)
    }

    @Test @MainActor func previewLayoutPreservesSplitFractions() {
        let first = MacWorkspacePane(intent: .local)
        let second = MacWorkspacePane(intent: .local)
        let root = MacWorkspaceNode.split(MacWorkspaceSplit(axis: .horizontal,
            fraction: 0.3, first: .pane(first), second: .pane(second)))
        let layout = MacWorkspaceLayout(root: root, in: CGRect(x: 0, y: 0, width: 408, height: 250))
        #expect(layout.paneFrames[first.id]?.width == 120)
        #expect(layout.paneFrames[second.id]?.width == 280)
        #expect(layout.paneFrames[first.id]?.height == 250)
    }

    @Test @MainActor func incomingDropRetainsProviderFileAndCleansOwnedStaging() async throws {
        let source = try SFTPDropStaging()
        let file = source.directory.appendingPathComponent("photo.png")
        let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10])
        try bytes.write(to: file)
        let provider = NSItemProvider()
        provider.suggestedName = "Vacation"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
                                            fileOptions: [], visibility: .all) { completion in
            completion(file, false, nil)
            return nil
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let incoming = try #require(SFTPIncomingDrop(providers: [provider], pasteboard: board))
        var result: (urls: [URL], staging: SFTPDropStaging)? = try await incoming.materialize()
        let retained = try #require(result?.urls.first)
        #expect(retained.lastPathComponent == "Vacation.png")
        #expect(retained != file)
        #expect(try Data(contentsOf: retained) == bytes)
        let ownedDirectory = try #require(result?.staging.directory)
        result = nil
        // `SFTPDropStaging` cleans up in `deinit`, and dropping the last reference does not
        // guarantee the deallocation happens on *this* statement — an autorelease pool or the
        // optimizer can defer it. Asserting immediately made this test fail roughly one run in
        // four under the parallel suite while passing every time in isolation. Waiting briefly
        // keeps exactly what the test is for — the directory does go away once nothing holds it —
        // without depending on when.
        var cleaned = false
        for _ in 0..<100 where !cleaned {
            if !FileManager.default.fileExists(atPath: ownedDirectory.path) { cleaned = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(cleaned, "staging directory outlived its last reference")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test @MainActor func incomingDropUsesNativeFileURLsAndRejectsUnsafeNames() async throws {
        let staging = try SFTPDropStaging()
        let file = staging.directory.appendingPathComponent("local.txt")
        try Data("drop".utf8).write(to: file)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([file as NSURL])
        let incoming = try #require(SFTPIncomingDrop(providers: [], pasteboard: board))
        let result = try await incoming.materialize()
        #expect(result.urls == [file])
        #expect(staging.owns(file.resolvingSymlinksInPath()))
        #expect(!staging.owns(staging.directory.deletingLastPathComponent().appendingPathComponent("outside.txt")))
        #expect(SFTPDropStaging.filename("../escape", fallback: "safe.png") == "safe.png")
        #expect(SFTPDropStaging.filename(".", fallback: "safe.png") == "safe.png")
        #expect(SFTPDropStaging.filename("Photo.jpg", fallback: "safe.png") == "Photo.jpg")
    }

    @Test @MainActor func incomingDropPropagatesExportFailure() async throws {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
                                            fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CocoaError(.fileReadNoPermission))
            return nil
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let incoming = try #require(SFTPIncomingDrop(providers: [provider], pasteboard: board))
        do {
            _ = try await incoming.materialize()
            Issue.record("A failed source export must not become an upload")
        } catch { #expect(!Task.isCancelled) }
    }

    @Test @MainActor func incomingDropRecognizesNativePromiseWithoutExportingDuringHover() throws {
        let delegate = IncomingPromiseTestDelegate()
        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: delegate)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.writeObjects([provider]))
        #expect(SFTPIncomingDrop(providers: [], pasteboard: board) != nil)
        #expect(!delegate.requestedWrite)
        withExtendedLifetime(delegate) {}
    }

    @Test @MainActor func workgroupStartsAllTabsAndClosingTabsLeavesDefinitionUnchanged() async throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let directory = FileManager.default.temporaryDirectory.appending(path: "glas-workgroup-start-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preset = LayoutPreset(name: "Eager", sessionIntents: (0..<2).map {
            .init(kind: .local, startupCommand: "printf started > tab-\($0)",
                  localShell: "/bin/sh", localDirectory: directory.path)
        })
        let originalDefinition = preset
        let broker = MacStartupCommandBroker()
        let request = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
        let window = MacWorkspaceWindowController(request: request, startupCommandBroker: broker, defaults: fixture.defaults)
        let manager = SessionManager(loadImmediately: false)
        let settings = SettingsManager(loadImmediately: false)
        defer { window.closeAllSessions(sessionManager: manager) }
        for tab in window.tabs {
            tab.startLocalPanes(sessionManager: manager, settingsManager: settings, onEmpty: {})
        }
        #expect(await waitForCondition(seconds: 3) {
            (0..<2).allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: "tab-\($0)").path) }
                && window.tabs.allSatisfy { $0.closeWarning == nil }
        })
        #expect(window.tabs.count == 2)
        let second = window.tabs[1]
        #expect(!window.removeTab(window.selectedTabID, sessionManager: manager))
        #expect(window.selectedTabID == second.workspaceID)
        #expect(second.localRuntimesByPaneID.values.allSatisfy { $0.processState.isRunning })
        #expect(window.removeTab(second.workspaceID, sessionManager: manager))
        #expect(second.isClosed)
        #expect(preset == originalDefinition)
    }

    @Test @MainActor func failedSSHLaunchRetriesOnlyAnUndispatchedStartupCommand() async throws {
        final class FailedLaunchManager: SessionManager {
            var receivedCommands: [String?] = []
            var dispatchBeforeFailure = false

            override func createAuthorizedSessionByServerID(
                _ serverID: UUID,
                settingsManager: SettingsManager,
                startupCommand: String? = nil,
                initialTerminalPresentation: TerminalSession.InitialTerminalPresentationRequest? = nil
            ) async throws -> AuthorizedSessionLaunch {
                receivedCommands.append(startupCommand)
                let session = TerminalSession(server: ServerConfiguration(name: "Unavailable", host: "unavailable.test", username: "tester"))
                session.installStartupCommand(startupCommand)
                initialTerminalPresentation?(session)
                if dispatchBeforeFailure { session.state = .connected }
                session.state = .error("Connection lost")
                return AuthorizedSessionLaunch(session: session)
            }
        }
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let broker = MacStartupCommandBroker()
        let preset = LayoutPreset(name: "Remote", sessionIntents: [.init(serverID: UUID(), startupCommand: "echo START_ONCE")])
        let request = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
        let controller = MacWorkspaceController(request: request, startupCommandBroker: broker, defaults: fixture.defaults)
        let pane = try #require(controller.focusedPane)
        let manager = FailedLaunchManager(loadImmediately: false)
        let settings = SettingsManager(loadImmediately: false)
        await controller.prepareSSHPaneIfNeeded(pane, sessionManager: manager, settingsManager: settings)
        #expect(controller.session(for: pane.id) == nil)
        controller.retryPane(pane.id)
        manager.dispatchBeforeFailure = true
        await controller.prepareSSHPaneIfNeeded(pane, sessionManager: manager, settingsManager: settings)
        #expect(controller.session(for: pane.id) == nil)
        controller.retryPane(pane.id)
        await controller.prepareSSHPaneIfNeeded(pane, sessionManager: manager, settingsManager: settings)
        #expect(manager.receivedCommands.count == 3)
        #expect(manager.receivedCommands[0] == "echo START_ONCE")
        #expect(manager.receivedCommands[1] == "echo START_ONCE")
        #expect(manager.receivedCommands[2] == nil)
    }

    @Test @MainActor func restoredWorkspaceRecapturesConfiguredCommandWithoutExecutingIt() throws {
        let preset = LayoutPreset(name: "Project", sessionIntents: [
            .init(kind: .local, startupCommand: "echo RESTORED_CONFIG", localShell: " ", localDirectory: "")
        ])
        #expect(preset.isValidForPersistence)
        let broker = MacStartupCommandBroker()
        let request = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
        let suite = "WorkspaceCaptureTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let live = MacWorkspaceWindowController(request: request, startupCommandBroker: broker, defaults: defaults)
        let paneID = try #require(live.selectedTab.focusedPaneID)
        #expect(live.selectedTab.claimStartupCommand(for: paneID)?.command == "echo RESTORED_CONFIG")
        let restored = MacWorkspaceWindowController(request: request, startupCommandBroker: broker, defaults: defaults)
        #expect(restored.selectedTab.claimStartupCommand(for: paneID) == nil)
        let captured = try restored.capturePreset(name: "Tomorrow", servers: [], sourcePresets: [preset])
        #expect(captured.sessionIntents[0].startupCommand == "echo RESTORED_CONFIG")
        #expect(captured.sessionIntents[0].localShell == nil)
        #expect(captured.sessionIntents[0].localDirectory == nil)
        #expect(!String(decoding: try JSONEncoder().encode(restored.selectedTab.state), as: UTF8.self).contains("RESTORED_CONFIG"))
    }

    @Test func overdeepSavedLayoutFailsDuringDecoding() throws {
        var node = LayoutPreset.WorkspaceLayout.Node.session(0)
        for _ in 0..<13 {
            node = .split(axis: .horizontal, fraction: 0.5, first: node, second: .session(1))
        }
        let data = try JSONEncoder().encode(node)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LayoutPreset.WorkspaceLayout.Node.self, from: data)
        }
    }

    @Test @MainActor func unvisitedPresetTabsRestoreTheirCompleteLayoutWithoutCommands() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let preset = LayoutPreset(name: "Project", sessionIntents: [
            .init(kind: .local, startupCommand: "echo NEVER_REPLAY"),
            .init(kind: .ssh, serverID: UUID()),
            .init(kind: .local, localDirectory: "/tmp")
        ], workspaceLayout: .init(tabs: [
            .init(label: "Unvisited", root: .split(axis: .vertical, fraction: 0.3,
                first: .session(0), second: .session(1)), focusedSessionIndex: 1),
            .init(label: "Selected", root: .session(2), focusedSessionIndex: 2)
        ], selectedTabIndex: 1))
        let broker = MacStartupCommandBroker()
        let request = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
        let live = MacWorkspaceWindowController(request: request, startupCommandBroker: broker, defaults: fixture.defaults)
        // No pane focus, startup ticket claim, or layout mutation before restoring.
        let descriptorsOnly = MacWorkspaceLaunchRequest(windowID: request.windowID,
            tabs: live.tabs.map { $0.restorationDescriptor.request })
        let restored = MacWorkspaceWindowController(request: descriptorsOnly,
            startupCommandBroker: broker, defaults: fixture.defaults)
        #expect(restored.tabs.map(\.state) == live.tabs.map(\.state))
        #expect(restored.selectedTabID == live.tabs[1].workspaceID)
        for tab in restored.tabs {
            for pane in tab.state.root?.panes ?? [] {
                #expect(tab.claimStartupCommand(for: pane.id) == nil)
            }
        }
    }

    @Test @MainActor func completePresetRoundTripsAndLaunchesFreshWithoutCommandSerialization() throws {
        let layout = LayoutPreset.WorkspaceLayout(tabs: [
            .init(label: "Project", root: .split(axis: .vertical, fraction: 0.35,
                                                first: .session(0), second: .session(1)), focusedSessionIndex: 1)
        ], selectedTabIndex: 0)
        let preset = LayoutPreset(name: "Project", sessionIntents: [
            .init(kind: .local, startupCommand: "echo UNIQUE_STARTUP_COMMAND", localShell: "/bin/zsh", localDirectory: "/tmp"),
            .init(kind: .local)
        ], workspaceLayout: layout)
        #expect(preset.isValidForPersistence)
        #expect(try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset)) == preset)
        let broker = MacStartupCommandBroker()
        let first = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
        let second = try MacWorkgroupLauncher.launch(preset: preset, broker: broker, openWindow: { _ in })[0]
        #expect(first.windowID != second.windowID)
        #expect(first.tabs[0].initialState?.root?.paneIDs != second.tabs[0].initialState?.root?.paneIDs)
        #expect(!String(decoding: try JSONEncoder().encode(first), as: UTF8.self).contains("UNIQUE_STARTUP_COMMAND"))
        let defaults = UserDefaults(suiteName: "WorkspacePresetTests.\(UUID())")!
        let controller = MacWorkspaceController(request: first, startupCommandBroker: broker, defaults: defaults)
        let pane = try #require(controller.state.root?.panes.first)
        #expect(controller.claimStartupCommand(for: pane.id)?.command == "echo UNIQUE_STARTUP_COMMAND")
        #expect(controller.claimStartupCommand(for: pane.id) == nil)
        let replay = MacWorkspaceController(request: first, startupCommandBroker: broker, defaults: defaults)
        #expect(replay.claimStartupCommand(for: pane.id) == nil)
    }

    @Test func savedLayoutRejectsMissingDuplicateAndInvalidFocus() {
        let duplicate = LayoutPreset.WorkspaceLayout(tabs: [
            .init(label: nil, root: .split(axis: .horizontal, fraction: 0.5,
                                         first: .session(0), second: .session(0)), focusedSessionIndex: 0)
        ], selectedTabIndex: 0)
        #expect(!duplicate.isValid(sessionCount: 2))
        let missing = LayoutPreset.WorkspaceLayout(tabs: [.init(label: nil, root: .session(0), focusedSessionIndex: 0)], selectedTabIndex: 0)
        #expect(!missing.isValid(sessionCount: 2))
        let focus = LayoutPreset.WorkspaceLayout(tabs: [.init(label: nil, root: .session(0), focusedSessionIndex: 1)], selectedTabIndex: 0)
        #expect(!focus.isValid(sessionCount: 1))
        let legacy = LayoutPreset.SessionIntent(schemaVersion: 2, kind: .local).migratedToCurrentSchema()
        #expect(legacy.isSupported)
        #expect(legacy.localDirectory == nil)
    }

    @Test @MainActor func windowCloseGatePreservesDelegateAndFinalizesOnlyOnce() {
        final class OriginalDelegate: NSObject, NSWindowDelegate {
            var allowsClose = false
            func windowShouldClose(_ sender: NSWindow) -> Bool { allowsClose }
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let original = OriginalDelegate()
        window.delegate = original
        let coordinator = MacTerminalWindowReader.Coordinator()
        var cleanupCount = 0
        coordinator.observeWindowClose(window) { cleanupCount += 1 }
        coordinator.interceptWindowClose(window, shouldConfirm: { false })

        #expect(window.delegate === coordinator)
        #expect(!coordinator.windowShouldClose(window))
        #expect(cleanupCount == 0)
        original.allowsClose = true
        #expect(coordinator.windowShouldClose(window))
        coordinator.finishSessions()
        window.close()
        #expect(cleanupCount == 1)
        coordinator.restoreWindowDelegate()
        #expect(window.delegate === original)
        coordinator.stopObservingWindowClose()
        #expect(!MacTerminalWindowReader.Coordinator.active.allObjects.contains { $0 === coordinator })
    }

    @Test @MainActor func windowCloseGateRefreshesConfirmationPreference() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let coordinator = MacTerminalWindowReader.Coordinator()
        var confirmationEnabled = true
        coordinator.observeWindowClose(window, action: {})
        coordinator.interceptWindowClose(window, shouldConfirm: { confirmationEnabled })
        #expect(coordinator.requiresCloseConfirmation)
        confirmationEnabled = false
        #expect(!coordinator.requiresCloseConfirmation)
        coordinator.restoreWindowDelegate()
        coordinator.stopObservingWindowClose()
        window.close()
    }

    private static let hostKeyValidationFixture =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJfkNV4OS33ImTXvorZr72q4v5XhVEQKfvqsxOEJ/XaR"

    @Test func legacyMacDefaultsMigrationCopiesOnlyAllowlistedNonsecretValues() throws {
        let suiteName = "sh.glas.legacy-migration-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        var legacyServer = ServerConfiguration(
            name: "Legacy",
            host: "legacy.test",
            username: "tester"
        )
        legacyServer.trustedHostKeys = [
            TrustedHostKeyEntry(
                host: "legacy.test",
                port: 22,
                algorithm: "ssh-ed25519",
                fingerprintSHA256: "SHA256:test",
                keyDataBase64: "dGVzdA==",
                addedAt: Date()
            )
        ]
        let workspaceKey = "\(UserDefaultsKeys.macWorkspaceRestoration).workspace"
        let legacyDomain: [String: Any] = [
            UserDefaultsKeys.servers: try JSONEncoder().encode([legacyServer]),
            UserDefaultsKeys.windowOpacity: 0.42,
            workspaceKey: Data("workspace".utf8),
            UserDefaultsKeys.trustedHostKeys: Data("global-trust".utf8),
            "password": "must-not-migrate",
            "unexpectedKey": "must-not-migrate",
        ]

        SharedDefaults.migrateLegacyMacDomainIfNeeded(
            legacyDomain: legacyDomain,
            destination: defaults
        )

        // D26: saved servers are **not** migrated any more. The catalog is the one store for a
        // connection, and the decision was explicitly that the new build reads nothing old — so a
        // legacy `servers` blob is left where it is rather than copied forward.
        #expect(defaults.object(forKey: UserDefaultsKeys.servers) == nil,
                "the legacy server catalog was copied forward; D26 says it must not be")
        // Settings still come across: they are not connections.
        #expect(defaults.double(forKey: UserDefaultsKeys.windowOpacity) == 0.42)
        #expect(defaults.data(forKey: workspaceKey) == Data("workspace".utf8))
        #expect(defaults.object(forKey: UserDefaultsKeys.trustedHostKeys) == nil)
        #expect(defaults.object(forKey: "password") == nil)
        #expect(defaults.object(forKey: "unexpectedKey") == nil)
        #expect(defaults.bool(forKey: SharedDefaults.legacyMacDomainMigrationSentinel))
    }

    @Test func legacyMacDefaultsMigrationPreservesExistingDestinationValuesAndRunsOnce() throws {
        let suiteName = "sh.glas.legacy-migration-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(0.75, forKey: UserDefaultsKeys.windowOpacity)

        SharedDefaults.migrateLegacyMacDomainIfNeeded(
            legacyDomain: [UserDefaultsKeys.windowOpacity: 0.25],
            destination: defaults
        )
        SharedDefaults.migrateLegacyMacDomainIfNeeded(
            legacyDomain: [UserDefaultsKeys.windowOpacity: 0.10],
            destination: defaults
        )

        #expect(defaults.double(forKey: UserDefaultsKeys.windowOpacity) == 0.75)
        #expect(defaults.bool(forKey: SharedDefaults.legacyMacDomainMigrationSentinel))
    }

    /// Replaces `legacyMacDefaultsMigrationRetriesAnUnreadableServerCatalog`, which tested
    /// machinery D26 removed: the migration used to sanitise a legacy server catalog before
    /// copying it, and to withhold its completion sentinel so an unreadable one would be retried
    /// on a later launch. Saved servers are not migrated at all now — the catalog is the one store
    /// for a connection, and the new build reads nothing old — so there is nothing to retry.
    @Test func legacyMacDefaultsMigrationIgnoresAnUnreadableServerCatalogAndStillCompletes() throws {
        let suiteName = "sh.glas.legacy-migration-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        SharedDefaults.migrateLegacyMacDomainIfNeeded(
            legacyDomain: [
                UserDefaultsKeys.servers: Data("not-json".utf8),
                UserDefaultsKeys.windowOpacity: 0.42,
            ],
            destination: defaults
        )

        // Not copied, not sanitised, not a reason to come back: simply not this build's business.
        #expect(defaults.object(forKey: UserDefaultsKeys.servers) == nil)
        // The settings beside it still migrate, and the pass is finished rather than pending.
        #expect(defaults.double(forKey: UserDefaultsKeys.windowOpacity) == 0.42)
        #expect(defaults.bool(forKey: SharedDefaults.legacyMacDomainMigrationSentinel),
                "an unreadable server catalog no longer holds the migration open")
    }

    @Test func restorationStateRoundTripsEveryPaneIntentAndSplitProperty() throws {
        let workspaceID = UUID()
        let serverID = UUID()
        let localPane = MacWorkspacePane(id: UUID(), intent: .local)
        let sshPane = MacWorkspacePane(id: UUID(), intent: .ssh(serverID: serverID))
        let split = MacWorkspaceSplit(
            id: UUID(),
            axis: .vertical,
            fraction: 0.37,
            first: .pane(localPane),
            second: .pane(sshPane)
        )
        var state = MacWorkspaceRestorationState(id: workspaceID)
        state.root = .split(split)
        state.focusedPaneID = sshPane.id

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            MacWorkspaceRestorationState.self,
            from: encoded
        )

        #expect(try decoded.validated(for: workspaceID) == state)
        #expect(decoded.root?.paneIDs == [localPane.id, sshPane.id])
        #expect(decoded.root?.pane(id: sshPane.id)?.intent.serverID == serverID)
    }

    @Test func blankLaunchRequestRoundTripsAndDecodesLegacyRequests() throws {
        let workspaceID = UUID()
        let request = MacWorkspaceLaunchRequest(
            workspaceID: workspaceID,
            startsEmpty: true
        )

        let decoded = try JSONDecoder().decode(
            MacWorkspaceLaunchRequest.self,
            from: JSONEncoder().encode(request)
        )
        #expect(decoded == request)

        let legacyData = try JSONSerialization.data(withJSONObject: [
            "workspaceID": workspaceID.uuidString
        ])
        let legacyRequest = try JSONDecoder().decode(
            MacWorkspaceLaunchRequest.self,
            from: legacyData
        )
        #expect(legacyRequest.workspaceID == workspaceID)
        #expect(!legacyRequest.startsEmpty)
        #expect(legacyRequest.startupTicketID == nil)
        #expect(legacyRequest.liveSessionTicketID == nil)
    }

    @Test func launchRequestRejectsMoreThanThirtyTwoTabsDuringDecode() throws {
        let tabs = (0...MacWorkspaceWindowRestorationState.maximumTabCount).map { _ in
            MacWorkspaceTabRequest(startsEmpty: true)
        }
        let tabsObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(tabs)
        )
        let data = try JSONSerialization.data(withJSONObject: [
            "windowID": UUID().uuidString,
            "tabs": tabsObject,
        ])

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MacWorkspaceLaunchRequest.self, from: data)
        }
    }

    @Test @MainActor func workgroupLaunchRequestCarriesOnlyDisplayMetadataAndOpaqueTicket() throws {
        let broker = MacStartupCommandBroker(capacity: 4)
        let secretCommand = "printf launch-secret-7f36"
        let ticketID = try #require(broker.issue(command: secretCommand))
        let workgroupID = UUID()
        let request = MacWorkspaceLaunchRequest(
            initialPaneIntent: .local,
            workgroupID: workgroupID,
            workgroupName: "Production",
            workgroupColor: .cyan,
            tabLabel: "Metrics",
            startupTicketID: ticketID
        )

        let encoded = try JSONEncoder().encode(request)
        let encodedText = try #require(String(data: encoded, encoding: .utf8))
        #expect(!encodedText.contains(secretCommand))
        #expect(encodedText.contains(ticketID.uuidString))

        let decoded = try JSONDecoder().decode(MacWorkspaceLaunchRequest.self, from: encoded)
        #expect(decoded == request)
        #expect(decoded.workgroupID == workgroupID)
        #expect(decoded.workgroupName == "Production")
        #expect(decoded.workgroupColor == .cyan)
        #expect(decoded.tabLabel == "Metrics")
        #expect(decoded.initialPaneIntent == .local)
    }

    @Test @MainActor func startupCommandBrokerIsBoundedAndClaimsExactlyOnce() throws {
        let broker = MacStartupCommandBroker(capacity: 2)
        let first = try #require(broker.issue(command: "echo first"))
        let second = try #require(broker.issue(command: "echo second"))
        let third = try #require(broker.issue(command: "echo third"))

        #expect(broker.pendingCount == 2)
        #expect(broker.claim(first) == nil)
        #expect(broker.claim(second)?.command == "echo second")
        #expect(broker.claim(second) == nil)
        #expect(broker.claim(third)?.command == "echo third")
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func abandonedStartupCommandTicketExpires() async throws {
        let broker = MacStartupCommandBroker(
            capacity: 1,
            expiration: .milliseconds(10)
        )
        let ticketID = try #require(broker.issue(command: "echo expiring"))

        try await Task.sleep(for: .milliseconds(30))

        #expect(broker.claim(ticketID) == nil)
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func liveSessionBrokerIsBoundedAndClaimsExactlyOnce() throws {
        let broker = MacLiveSessionBroker(capacity: 1)
        let first = TerminalSession(
            server: ServerConfiguration(name: "First", host: "first.test", username: "tester")
        )
        let second = TerminalSession(
            server: ServerConfiguration(name: "Second", host: "second.test", username: "tester")
        )
        var discardedSessionIDs: [UUID] = []
        let firstTicketID = broker.issue(session: first) {
            discardedSessionIDs.append(first.id)
        }
        let secondTicketID = broker.issue(session: second) {
            discardedSessionIDs.append(second.id)
        }

        #expect(discardedSessionIDs == [first.id])
        #expect(broker.pendingCount == 1)
        #expect(broker.claim(firstTicketID) == nil)
        #expect(broker.claim(secondTicketID)?.session === second)
        #expect(broker.claim(secondTicketID) == nil)
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func abandonedLiveSessionTicketExpiresAndRunsCleanup() async throws {
        let broker = MacLiveSessionBroker(
            capacity: 1,
            expiration: .milliseconds(10)
        )
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Expiring",
                host: "expiring.test",
                username: "tester"
            )
        )
        var discarded = false
        _ = broker.issue(session: session) {
            discarded = true
        }

        try await Task.sleep(for: .milliseconds(30))

        #expect(discarded)
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func workspaceClaimsPreparedLiveSessionWithoutReconnecting() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let broker = MacLiveSessionBroker()
        let sessionManager = SessionManager(loadImmediately: false)
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Transient",
                host: "transient.test",
                username: "tester"
            )
        )
        let request = MacLiveSessionWorkspaceRouter.launchRequest(
            for: session,
            sessionManager: sessionManager,
            broker: broker
        )
        let controller = MacWorkspaceController(
            request: request,
            liveSessionBroker: broker,
            defaults: fixture.defaults
        )
        let paneID = try #require(controller.focusedPaneID)

        #expect(
            request.initialPaneIntent
                == MacWorkspacePaneIntent.ssh(serverID: session.server.id)
        )
        #expect(request.liveSessionTicketID != nil)
        let encodedRequest = try JSONEncoder().encode(request)
        let encodedText = try #require(String(data: encodedRequest, encoding: .utf8))
        #expect(!encodedText.contains("transient.test"))
        #expect(!encodedText.contains("tester"))
        #expect(controller.session(for: paneID) === session)
        #expect(controller.error(for: paneID) == nil)
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func restoredWorkspaceDiscardsPreparedLiveSessionTicket() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let original = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        original.focus(try #require(original.focusedPaneID))

        let broker = MacLiveSessionBroker()
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Restored",
                host: "restored.test",
                username: "tester"
            )
        )
        var discarded = false
        let ticketID = broker.issue(session: session) {
            discarded = true
        }
        let restored = MacWorkspaceController(
            request: MacWorkspaceLaunchRequest(
                workspaceID: fixture.workspaceID,
                initialPaneIntent: .ssh(serverID: session.server.id),
                liveSessionTicketID: ticketID
            ),
            liveSessionBroker: broker,
            defaults: fixture.defaults
        )

        #expect(restored.sessionsByPaneID.isEmpty)
        #expect(discarded)
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func restoredWorkspaceNeverReplaysStartupTicket() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let original = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        original.focus(try #require(original.focusedPaneID))

        let broker = MacStartupCommandBroker()
        let ticketID = try #require(broker.issue(command: "echo must-not-replay"))
        let restored = MacWorkspaceController(
            request: MacWorkspaceLaunchRequest(
                workspaceID: fixture.workspaceID,
                initialPaneIntent: .local,
                startupTicketID: ticketID
            ),
            startupCommandBroker: broker,
            defaults: fixture.defaults
        )

        #expect(restored.claimStartupCommand(for: try #require(restored.focusedPaneID)) == nil)
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func workgroupLauncherCreatesAClaimableSingleUseRequest() throws {
        let broker = MacStartupCommandBroker()
        var opened: [MacWorkspaceLaunchRequest] = []
        let requests = MacWorkgroupLauncher.launch(
            workgroupID: UUID(),
            name: "Operations",
            color: .orange,
            items: [MacWorkgroupLaunchItem(
                intent: .local,
                label: "Local",
                startupCommand: "uptime"
            )],
            broker: broker,
            openWindow: { opened.append($0) }
        )

        #expect(opened.count == 1)
        let request = try #require(requests.first)
        #expect(opened[0].tabs.map(\.workspaceID) == [request.workspaceID])
        #expect(request.workgroupName == "Operations")
        #expect(request.tabLabel == "Local")
        #expect(request.workgroupColor == .orange)
        #expect(broker.claim(try #require(request.startupTicketID))?.command == "uptime")
        #expect(broker.pendingCount == 0)
    }


    @Test @MainActor func windowControllerOwnsStableOrderedTabsAndSelection() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let secondID = UUID()
        let request = MacWorkspaceLaunchRequest(
            windowID: fixture.workspaceID,
            tabs: [
                MacWorkspaceTabRequest(
                    workspaceID: fixture.workspaceID,
                    initialPaneIntent: .local,
                    tabLabel: "Local"
                ),
                MacWorkspaceTabRequest(
                    workspaceID: secondID,
                    startsEmpty: true,
                    tabLabel: "SSH"
                ),
            ]
        )
        let controller = MacWorkspaceWindowController(
            request: request,
            defaults: fixture.defaults
        )

        #expect(controller.tabs.map(\.workspaceID) == [fixture.workspaceID, secondID])
        #expect(controller.selectedTabID == fixture.workspaceID)
        controller.select(secondID)
        #expect(controller.selectedTab.workspaceID == secondID)
    }

    @Test @MainActor func windowControllerAddsAndRestoresModelOwnedTabs() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let controller = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                workspaceID: fixture.workspaceID,
                startsEmpty: true
            ),
            defaults: fixture.defaults
        )
        let added = try #require(
            controller.addTab(
                MacWorkspaceTabRequest(startsEmpty: true, tabLabel: "Second")
            )
        )

        let restored = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                workspaceID: fixture.workspaceID,
                startsEmpty: true
            ),
            defaults: fixture.defaults
        )
        #expect(restored.tabs.map(\.workspaceID) == [
            fixture.workspaceID,
            added.workspaceID,
        ])
        #expect(restored.selectedTabID == added.workspaceID)
        #expect(restored.tabs[1].tabLabel == "Second")
    }

    @Test @MainActor func tabTransferPreservesControllerIdentityAndLiveState() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let transferBroker = MacWorkspaceTransferBroker(
            capacity: 2,
            expiration: .seconds(30)
        )
        let source = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                windowID: fixture.workspaceID,
                tabs: [
                    MacWorkspaceTabRequest(workspaceID: fixture.workspaceID),
                    MacWorkspaceTabRequest(startsEmpty: true, tabLabel: "Detached"),
                ]
            ),
            transferBroker: transferBroker,
            defaults: fixture.defaults
        )
        source.select(try #require(source.tabs.last?.workspaceID))
        let transferred = source.selectedTab
        let request = try #require(source.transferSelectedTab())
        #expect(transferBroker.pendingCount == 1)
        #expect(source.tabs.count == 2)

        let destination = MacWorkspaceWindowController(
            request: request,
            transferBroker: transferBroker,
            defaults: fixture.defaults
        )
        #expect(destination.selectedTab === transferred)
        #expect(source.tabs.count == 1)
        #expect(transferBroker.pendingCount == 0)
    }

    @Test @MainActor func expiredTabTransferLeavesSourceUntouched() async throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let transferBroker = MacWorkspaceTransferBroker(
            capacity: 1,
            expiration: .milliseconds(10)
        )
        let source = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                windowID: fixture.workspaceID,
                tabs: [
                    MacWorkspaceTabRequest(workspaceID: fixture.workspaceID),
                    MacWorkspaceTabRequest(startsEmpty: true, tabLabel: "Stays Put"),
                ]
            ),
            transferBroker: transferBroker,
            defaults: fixture.defaults
        )
        source.select(try #require(source.tabs.last?.workspaceID))
        let originalIDs = source.tabs.map(\.workspaceID)
        let request = try #require(source.transferSelectedTab())

        try await Task.sleep(for: .milliseconds(30))
        #expect(transferBroker.pendingCount == 0)
        #expect(source.tabs.map(\.workspaceID) == originalIDs)
        #expect(source.selectedTabID == originalIDs[1])
        let destination = MacWorkspaceWindowController(
            request: request,
            transferBroker: transferBroker,
            defaults: fixture.defaults
        )
        #expect(destination.selectedTab.isEmpty)
        #expect(destination.selectedTab.localRuntimesByPaneID.isEmpty)
        #expect(destination.selectedTab.sessionsByPaneID.isEmpty)
    }

    @Test @MainActor func rapidDuplicateMoveIsRejectedUntilTransferResolves() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let broker = MacWorkspaceTransferBroker()
        let source = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                windowID: fixture.workspaceID,
                tabs: [
                    MacWorkspaceTabRequest(workspaceID: fixture.workspaceID),
                    MacWorkspaceTabRequest(startsEmpty: true),
                ]
            ),
            transferBroker: broker,
            defaults: fixture.defaults
        )
        source.select(try #require(source.tabs.last?.workspaceID))

        let first = try #require(source.transferSelectedTab())
        #expect(!source.canTransferSelectedTab)
        #expect(source.transferSelectedTab() == nil)
        #expect(broker.pendingCount == 1)

        _ = MacWorkspaceWindowController(
            request: first,
            transferBroker: broker,
            defaults: fixture.defaults
        )
        #expect(broker.pendingCount == 0)
        #expect(source.tabs.count == 1)
    }

    @Test @MainActor func sourceCloseCancelsPendingTransferAndDestinationFailsClosed() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let broker = MacWorkspaceTransferBroker()
        let sessionManager = SessionManager(loadImmediately: false)
        let source = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                windowID: fixture.workspaceID,
                tabs: [
                    MacWorkspaceTabRequest(workspaceID: fixture.workspaceID),
                    MacWorkspaceTabRequest(startsEmpty: true),
                ]
            ),
            transferBroker: broker,
            defaults: fixture.defaults
        )
        source.select(try #require(source.tabs.last?.workspaceID))
        let request = try #require(source.transferSelectedTab())

        source.closeAllSessions(sessionManager: sessionManager)
        #expect(broker.pendingCount == 0)
        let destination = MacWorkspaceWindowController(
            request: request,
            transferBroker: broker,
            defaults: fixture.defaults
        )
        #expect(destination.tabs.count == 1)
        #expect(destination.selectedTab.isEmpty)
        #expect(destination.selectedTab.localRuntimesByPaneID.isEmpty)
        #expect(destination.selectedTab.sessionsByPaneID.isEmpty)
    }

    @Test @MainActor func transferCommitFailureKeepsSourceAndFailsClosed() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let broker = MacWorkspaceTransferBroker()
        let sessionManager = SessionManager(loadImmediately: false)
        let source = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                windowID: fixture.workspaceID,
                tabs: [
                    MacWorkspaceTabRequest(workspaceID: fixture.workspaceID),
                    MacWorkspaceTabRequest(startsEmpty: true),
                ]
            ),
            transferBroker: broker,
            defaults: fixture.defaults
        )
        let nonTransferredID = source.selectedTabID
        source.select(try #require(source.tabs.last?.workspaceID))
        let transferredID = source.selectedTabID
        let request = try #require(source.transferSelectedTab())
        #expect(
            !source.removeTab(
                nonTransferredID,
                sessionManager: sessionManager
            )
        )

        let destination = MacWorkspaceWindowController(
            request: request,
            transferBroker: broker,
            defaults: fixture.defaults
        )
        #expect(broker.pendingCount == 0)
        #expect(source.tabs.map(\.workspaceID) == [transferredID])
        #expect(source.selectedTabID == transferredID)
        #expect(destination.selectedTab.isEmpty)
        #expect(destination.selectedTab.sessionsByPaneID.isEmpty)
    }

    @Test @MainActor func transferCapacityEvictionLeavesSourceAndFailsClosed() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let broker = MacWorkspaceTransferBroker(capacity: 1)
        let firstWindowID = UUID()
        let secondWindowID = UUID()
        let firstSource = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                windowID: firstWindowID,
                tabs: [
                    MacWorkspaceTabRequest(workspaceID: firstWindowID),
                    MacWorkspaceTabRequest(startsEmpty: true),
                ]
            ),
            transferBroker: broker,
            defaults: fixture.defaults
        )
        let secondSource = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                windowID: secondWindowID,
                tabs: [
                    MacWorkspaceTabRequest(workspaceID: secondWindowID),
                    MacWorkspaceTabRequest(startsEmpty: true),
                ]
            ),
            transferBroker: broker,
            defaults: fixture.defaults
        )
        firstSource.select(try #require(firstSource.tabs.last?.workspaceID))
        secondSource.select(try #require(secondSource.tabs.last?.workspaceID))
        let retainedWorkspaceID = secondSource.selectedTabID
        let evictedRequest = try #require(firstSource.transferSelectedTab())
        let retainedRequest = try #require(secondSource.transferSelectedTab())

        #expect(firstSource.tabs.count == 2)
        #expect(firstSource.canTransferSelectedTab)
        #expect(broker.pendingCount == 1)
        let destination = MacWorkspaceWindowController(
            request: evictedRequest,
            transferBroker: broker,
            defaults: fixture.defaults
        )
        #expect(destination.selectedTab.isEmpty)
        #expect(destination.selectedTab.localRuntimesByPaneID.isEmpty)
        #expect(broker.pendingCount == 1)
        let retainedDestination = MacWorkspaceWindowController(
            request: retainedRequest,
            transferBroker: broker,
            defaults: fixture.defaults
        )
        #expect(retainedDestination.selectedTab.workspaceID == retainedWorkspaceID)
        #expect(secondSource.tabs.count == 1)
        #expect(broker.pendingCount == 0)
    }

    @Test @MainActor func windowTabCapAndLastTabRemovalPreserveInvariants() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let sessionManager = SessionManager(loadImmediately: false)
        let controller = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                workspaceID: fixture.workspaceID,
                startsEmpty: true
            ),
            defaults: fixture.defaults
        )
        for _ in 1..<MacWorkspaceWindowRestorationState.maximumTabCount {
            #expect(controller.addTab() != nil)
        }
        let windowStorageKey = "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(fixture.workspaceID.uuidString.lowercased())"
        let before = fixture.defaults.data(forKey: windowStorageKey)
        #expect(!controller.canAddTab)
        #expect(controller.addTab() == nil)
        #expect(controller.tabs.count == MacWorkspaceWindowRestorationState.maximumTabCount)
        #expect(fixture.defaults.data(forKey: windowStorageKey) == before)

        let single = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(startsEmpty: true),
            defaults: fixture.defaults
        )
        let retainedID = single.selectedTabID
        #expect(single.removeTab(retainedID, sessionManager: sessionManager))
        #expect(single.tabs.count == 1)
        #expect(single.selectedTabID == retainedID)
        #expect(single.selectedTab.workspaceID == retainedID)
    }

    @Test @MainActor func workgroupLauncherOpensOneWindowWithOrderedTabs() throws {
        let broker = MacStartupCommandBroker()
        var opened: [MacWorkspaceLaunchRequest] = []
        let returned = MacWorkgroupLauncher.launch(
            workgroupID: UUID(),
            name: "Operations",
            color: .orange,
            items: [
                MacWorkgroupLaunchItem(intent: .local, label: "One"),
                MacWorkgroupLaunchItem(intent: .local, label: "Two"),
            ],
            broker: broker,
            openWindow: { opened.append($0) }
        )

        #expect(opened.count == 1)
        #expect(opened[0].tabs.map(\.tabLabel) == ["One", "Two"])
        #expect(returned.map(\.workspaceID) == opened[0].tabs.map(\.workspaceID))
    }

    @Test @MainActor func appleTerminalThemeImporterUsesOnlyAllowlistedVisualFields() throws {
        let fallbackBackground = CodableColor(
            sRGBRed: 0.12,
            green: 0.23,
            blue: 0.34,
            alpha: 0.45
        )
        var fallback = TerminalTheme.default
        fallback.background = fallbackBackground
        let textColor = NSColor(
            calibratedRed: 0.95,
            green: 0.20,
            blue: 0.10,
            alpha: 1
        )
        let redColor = NSColor(
            calibratedRed: 0.80,
            green: 0.05,
            blue: 0.03,
            alpha: 1
        )
        let lightProfileBackground = NSColor(
            calibratedRed: 0.95,
            green: 0.94,
            blue: 0.92,
            alpha: 1
        )
        let profile: [String: Any] = [
            "name": "Imported Apple Profile",
            "TextColor": try NSKeyedArchiver.archivedData(
                withRootObject: textColor,
                requiringSecureCoding: true
            ),
            "ANSIRedColor": try NSKeyedArchiver.archivedData(
                withRootObject: redColor,
                requiringSecureCoding: true
            ),
            "Font": try NSKeyedArchiver.archivedData(
                withRootObject: NSFont(name: "Menlo", size: 17)!,
                requiringSecureCoding: true
            ),
            "BackgroundColor": try NSKeyedArchiver.archivedData(
                withRootObject: lightProfileBackground,
                requiringSecureCoding: true
            ),
            "BackgroundBlur": 0.9,
            "CommandString": "must never be imported",
            "WorkingDirectory": "/private/tmp",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: profile,
            format: .binary,
            options: 0
        )

        let imported = try TerminalThemeImportService.importTheme(
            from: data,
            fallback: fallback
        )

        #expect(imported.id == fallback.id)
        #expect(imported.name == "Imported Apple Profile")
        #expect(imported.background == fallbackBackground)
        #expect(imported.foreground.red > 0.9)
        #expect(imported.red.red > 0.75)
        #expect(imported.fontName == "Menlo-Regular")
        #expect(imported.fontSize == 17)
        #expect(imported.green == fallback.green)
        #expect(imported.preferredAppearance == .light)
    }

    @Test @MainActor func appleTerminalThemeImporterRejectsInvalidAndOversizedInput() throws {
        let invalidProfile: [String: Any] = [
            "name": "Invalid",
            "TextColor": "not an archived NSColor",
        ]
        let invalidData = try PropertyListSerialization.data(
            fromPropertyList: invalidProfile,
            format: .binary,
            options: 0
        )

        #expect(throws: TerminalThemeImportError.self) {
            try TerminalThemeImportService.importTheme(
                from: invalidData,
                fallback: .default
            )
        }
        #expect(throws: TerminalThemeImportError.self) {
            try TerminalThemeImportService.importTheme(
                from: Data(count: TerminalThemeImportService.maximumImportBytes + 1),
                fallback: .default
            )
        }
    }

    @Test @MainActor func shippedAppleClearDarkProfileImportsWithMonospacedFallback() throws {
        let url = URL(
            fileURLWithPath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings/Clear Dark.terminal"
        )
        #expect(FileManager.default.fileExists(atPath: url.path))
        var fallback = TerminalTheme.default
        fallback.fontName = "SF Mono"
        fallback.fontSize = 14
        let fallbackBackground = fallback.background

        let imported = try TerminalThemeImportService.importTheme(
            from: url,
            fallback: fallback
        )

        #expect(imported.name == "Clear Dark")
        #expect(imported.fontName == "SF Mono")
        #expect(imported.fontSize == 12)
        #expect(imported.background == fallbackBackground)
        #expect(imported.ansiColors.count == 16)
        #expect(imported.preferredAppearance == .dark)
    }

    @Test @MainActor func homebrewProfileInheritsAppleDefaultANSIPalette() throws {
        let url = URL(
            fileURLWithPath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings/Homebrew.terminal"
        )
        var fallback = TerminalTheme.default
        fallback.red = CodableColor(sRGBRed: 1, green: 0, blue: 1)

        let imported = try TerminalThemeImportService.importTheme(
            from: url,
            fallback: fallback
        )

        #expect(imported.name == "Homebrew")
        #expect(imported.foreground != TerminalTheme.appleClearDarkForeground)
        #expect(imported.ansiColors == TerminalTheme.appleClearDarkANSIColors)
        #expect(imported.preferredAppearance == .dark)
    }

    @Test @MainActor func blankFallbackNeverOverridesRestoredWorkspace() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }

        let blankController = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            startsEmptyIfUnrestored: true,
            defaults: fixture.defaults
        )
        #expect(blankController.isEmpty)

        blankController.addPane(intent: .local, axis: .vertical)
        let persistedPaneID = try #require(blankController.focusedPaneID)

        let restoredController = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            startsEmptyIfUnrestored: true,
            defaults: fixture.defaults
        )
        #expect(!restoredController.isEmpty)
        #expect(restoredController.focusedPaneID == persistedPaneID)
        #expect(restoredController.focusedPane?.intent == .local)
    }

    @Test func validationRejectsUnsupportedSchemasAndInvalidPaneIntentShapes() throws {
        let validState = MacWorkspaceRestorationState()
        let futureState = try replacingTopLevelValue(
            in: validState,
            key: "schemaVersion",
            value: MacWorkspaceRestorationState.currentSchemaVersion + 1
        )

        #expect(
            throws: MacWorkspaceStateError.unsupportedWorkspaceVersion(
                MacWorkspaceRestorationState.currentSchemaVersion + 1
            )
        ) {
            try futureState.validated()
        }

        let futureIntent = Data(
            #"{"schemaVersion":2,"kind":"local"}"#.utf8
        )
        #expect(throws: MacWorkspaceStateError.unsupportedPaneIntentVersion(2)) {
            try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: futureIntent)
        }

        let serverID = UUID()
        let localWithServer = Data(
            #"{"schemaVersion":1,"kind":"local","serverID":"\#(serverID.uuidString)"}"#.utf8
        )
        #expect(throws: MacWorkspaceStateError.invalidPaneIntent) {
            try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: localWithServer)
        }

        let sshWithoutServer = Data(
            #"{"schemaVersion":1,"kind":"ssh"}"#.utf8
        )
        #expect(throws: MacWorkspaceStateError.invalidPaneIntent) {
            try JSONDecoder().decode(MacWorkspacePaneIntent.self, from: sshWithoutServer)
        }
    }

    @Test func validationBindsWorkspaceIdentityAndFocusToExistingPanes() throws {
        let state = MacWorkspaceRestorationState()
        #expect(throws: MacWorkspaceStateError.workspaceIdentityMismatch) {
            try state.validated(for: UUID())
        }

        var missingFocus = state
        missingFocus.focusedPaneID = UUID()
        #expect(throws: MacWorkspaceStateError.invalidFocus) {
            try missingFocus.validated()
        }

        var emptyWithFocus = state
        emptyWithFocus.root = nil
        #expect(throws: MacWorkspaceStateError.invalidFocus) {
            try emptyWithFocus.validated()
        }

        emptyWithFocus.focusedPaneID = nil
        #expect(try emptyWithFocus.validated() == emptyWithFocus)
    }

    @Test func validationRejectsDuplicateNodeIdentity() {
        let duplicateID = UUID()
        let pane = MacWorkspacePane(id: duplicateID, intent: .local)
        var state = MacWorkspaceRestorationState()
        state.root = .split(MacWorkspaceSplit(
            axis: .horizontal,
            first: .pane(pane),
            second: .pane(pane)
        ))
        state.focusedPaneID = duplicateID

        #expect(throws: MacWorkspaceStateError.duplicateNodeIdentity) {
            try state.validated()
        }
    }

    @Test func validationRejectsInvalidFractionsDepthAndPaneCount() {
        for boundaryFraction in [0.1, 0.9] {
            var state = MacWorkspaceRestorationState()
            state.root = .split(MacWorkspaceSplit(
                axis: .vertical,
                fraction: boundaryFraction,
                first: .pane(MacWorkspacePane(intent: .local)),
                second: .pane(MacWorkspacePane(intent: .local))
            ))
            state.focusedPaneID = state.root?.paneIDs.first
            let validated = try? state.validated()
            #expect(validated == state)
        }

        for invalidFraction in [-1.0, 0.09, 0.91, 2.0, .infinity, .nan] {
            var state = MacWorkspaceRestorationState()
            state.root = .split(MacWorkspaceSplit(
                axis: .horizontal,
                fraction: invalidFraction,
                first: .pane(MacWorkspacePane(intent: .local)),
                second: .pane(MacWorkspacePane(intent: .local))
            ))
            state.focusedPaneID = state.root?.paneIDs.first

            #expect(throws: MacWorkspaceStateError.invalidSplitFraction) {
                try state.validated()
            }
        }

        var tooDeep = MacWorkspaceRestorationState()
        tooDeep.root = nestedNode(depth: MacWorkspaceRestorationState.maximumDepth + 1)
        tooDeep.focusedPaneID = tooDeep.root?.paneIDs.first
        #expect(throws: MacWorkspaceStateError.tooDeep) {
            try tooDeep.validated()
        }

        var tooMany = MacWorkspaceRestorationState()
        tooMany.root = balancedNode(
            paneCount: MacWorkspaceRestorationState.maximumPaneCount + 1
        )
        tooMany.focusedPaneID = tooMany.root?.paneIDs.first
        #expect(throws: MacWorkspaceStateError.tooManyPanes) {
            try tooMany.validated()
        }
    }

    @Test @MainActor func controllerWindowIdentityUsesLocalSavedHostAndFocusedSplit() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let server = ServerConfiguration(
            name: "Build Server",
            host: "build.internal",
            port: 2222,
            username: "builder"
        )
        let controller = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        let localPaneID = try #require(controller.focusedPaneID)

        for status in ["Starting", "Exited 1", "Failed"] {
            controller.updateLocalProcessStatus(status, for: localPaneID)
            #expect(controller.windowIdentity(servers: [], localUsername: "local-user").subtitle
                    == "local-user@localhost — \(status)")
        }
        controller.updateLocalProcessStatus(nil, for: localPaneID)

        #expect(
            controller.windowIdentity(
                servers: [server],
                localUsername: "local-user"
            ) == MacWorkspaceWindowIdentity(
                title: "Local",
                subtitle: "local-user@localhost"
            )
        )

        controller.addPane(
            intent: .ssh(serverID: server.id),
            axis: .horizontal
        )
        let sshPaneID = try #require(controller.focusedPaneID)
        #expect(sshPaneID != localPaneID)
        #expect(
            controller.windowIdentity(servers: [server])
                == MacWorkspaceWindowIdentity(
                    title: "Build Server",
                    subtitle: "builder@build.internal:2222"
                )
        )

        controller.focus(localPaneID)
        #expect(
            controller.windowIdentity(
                servers: [server],
                localUsername: "local-user"
            ) == MacWorkspaceWindowIdentity(
                title: "Local",
                subtitle: "local-user@localhost"
            )
        )

        controller.focus(sshPaneID)
        #expect(
            controller.windowIdentity(servers: [server])
                == MacWorkspaceWindowIdentity(
                    title: "Build Server",
                    subtitle: "builder@build.internal:2222"
                )
        )
    }

    @Test @MainActor func controllerWindowIdentityResolvesSavedSSHBeforeSessionStarts() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let server = ServerConfiguration(
            name: "Umbp",
            host: "192.0.2.11",
            username: "michael"
        )
        let controller = MacWorkspaceController(
            request: MacWorkspaceLaunchRequest(
                workspaceID: fixture.workspaceID,
                initialPaneIntent: .ssh(serverID: server.id)
            ),
            defaults: fixture.defaults
        )

        #expect(controller.sessionsByPaneID.isEmpty)
        #expect(
            controller.windowIdentity(servers: [server])
                == MacWorkspaceWindowIdentity(
                    title: "Umbp",
                    subtitle: "michael@192.0.2.11:22"
                )
        )
    }

    @Test func workspaceWindowIdentitySanitizesUntrustedChromeText() {
        let identity = MacWorkspaceWindowIdentity(
            title: "  Build\u{202E}\u{0000}\nServer  ",
            subtitle: " deploy\t@\rhost " + String(repeating: "x", count: 300)
        )
        let empty = MacWorkspaceWindowIdentity(
            title: "\n\t",
            subtitle: "\u{0000}"
        )

        #expect(identity.title == "Build Server")
        #expect(identity.subtitle?.hasPrefix("deploy @ host") == true)
        #expect(identity.subtitle?.count == 240)
        #expect(empty.title == "Terminal")
        #expect(empty.subtitle == nil)
    }

    @Test @MainActor func controllerSplitsFocusesClampsAndCollapsesPanes() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let controller = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        let sessionManager = SessionManager(loadImmediately: false)
        let initialPaneID = try #require(controller.focusedPaneID)

        controller.addPane(intent: .local, axis: .horizontal)
        let secondPaneID = try #require(controller.focusedPaneID)
        #expect(secondPaneID != initialPaneID)
        #expect(controller.state.root?.paneIDs == [initialPaneID, secondPaneID])

        let rootSplitID: UUID
        if case .split(let split) = controller.state.root {
            rootSplitID = split.id
            #expect(split.axis == .horizontal)
        } else {
            Issue.record("Adding a pane did not create a split root")
            return
        }

        controller.updateSplitFraction(rootSplitID, fraction: 4)
        if case .split(let split) = controller.state.root {
            #expect(split.fraction == 0.9)
        }

        controller.focus(initialPaneID)
        controller.addPane(intent: .ssh(serverID: UUID()), axis: .vertical)
        let thirdPaneID = try #require(controller.focusedPaneID)
        #expect(controller.state.root?.paneIDs == [initialPaneID, thirdPaneID, secondPaneID])
        #expect(controller.focusedPane?.intent.kind == .ssh)

        controller.focus(UUID())
        #expect(controller.focusedPaneID == thirdPaneID)
        controller.focusNextPane()
        #expect(controller.focusedPaneID == secondPaneID)
        controller.focusNextPane()
        #expect(controller.focusedPaneID == initialPaneID)

        controller.removePane(initialPaneID, sessionManager: sessionManager)
        #expect(controller.state.root?.paneIDs == [thirdPaneID, secondPaneID])
        #expect(controller.focusedPaneID == thirdPaneID)
        controller.removePane(thirdPaneID, sessionManager: sessionManager)
        controller.removePane(secondPaneID, sessionManager: sessionManager)
        #expect(controller.isEmpty)
        #expect(controller.focusedPaneID == nil)

        controller.addPane(intent: .local, axis: .vertical)
        #expect(controller.state.root?.paneIDs.count == 1)
        #expect(controller.focusedPane?.intent == .local)
    }

    @Test @MainActor func cleanSSHExitRemovesItsPaneAndClosesOnlyAnEmptyTab() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let controller = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        let sessionManager = SessionManager(loadImmediately: false)
        let localPaneID = try #require(controller.focusedPaneID)

        controller.addPane(intent: .ssh(serverID: UUID()), axis: .horizontal)
        let sshPaneID = try #require(controller.focusedPaneID)

        #expect(!controller.completeCleanSSHExit(sshPaneID, sessionManager: sessionManager))
        #expect(controller.state.root?.paneIDs == [localPaneID])
        #expect(controller.error(for: sshPaneID) == nil)

        controller.removePane(localPaneID, sessionManager: sessionManager)
        controller.addPane(intent: .ssh(serverID: UUID()), axis: .horizontal)
        let onlyPaneID = try #require(controller.focusedPaneID)

        #expect(controller.completeCleanSSHExit(onlyPaneID, sessionManager: sessionManager))
        #expect(controller.isEmpty)
        #expect(controller.error(for: onlyPaneID) == nil)
    }

    @Test @MainActor func controllerPersistsOnlyBoundedNonsecretRestorationData() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let serverID = UUID()
        let controller = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        controller.addPane(intent: .ssh(serverID: serverID), axis: .vertical)

        let persisted = try #require(fixture.defaults.data(forKey: fixture.storageKey))
        let text = try #require(String(data: persisted, encoding: .utf8))
        #expect(persisted.count <= 128 * 1024)
        #expect(text.localizedCaseInsensitiveContains(serverID.uuidString))

        let forbiddenKeys = [
            "password", "privatekey", "passphrase", "credential", "oauth",
            "token", "environmentvariables", "preparedauthentication", "pty"
        ]
        for key in forbiddenKeys {
            #expect(!text.localizedCaseInsensitiveContains(key))
        }
        let sentinelSecrets = [
            "workspace-test-password-7d98b7",
            "-----BEGIN OPENSSH " + "PRIVATE KEY-----",
            "workspace-test-oauth-secret-57bda1"
        ]
        for secret in sentinelSecrets {
            #expect(!text.contains(secret))
        }

        let restored = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        #expect(restored.state == controller.state)
        #expect(restored.sessionsByPaneID.isEmpty)
        #expect(restored.loadingPaneIDs.isEmpty)

        let oversized = Data(repeating: 0x41, count: 128 * 1024 + 1)
        fixture.defaults.set(oversized, forKey: fixture.storageKey)
        let boundedFallback = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        #expect(boundedFallback.workspaceID == fixture.workspaceID)
        #expect(boundedFallback.state.root == nil)
        #expect(boundedFallback.localRuntimesByPaneID.isEmpty)
        #expect(fixture.defaults.data(forKey: fixture.storageKey) == oversized)
    }

    @Test @MainActor func invalidRestorationDataFailsClosedWithoutCreatingAPTY() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }

        fixture.defaults.set(Data("{not-json".utf8), forKey: fixture.storageKey)
        let malformed = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        #expect(malformed.state.root == nil)
        #expect(malformed.localRuntimesByPaneID.isEmpty)

        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(MacWorkspaceRestorationState(id: fixture.workspaceID))
            ) as? [String: Any]
        )
        object["schemaVersion"] = MacWorkspaceRestorationState.currentSchemaVersion + 1
        let futureData = try JSONSerialization.data(withJSONObject: object)
        fixture.defaults.set(futureData, forKey: fixture.storageKey)
        let future = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        #expect(future.state.root == nil)
        #expect(future.localRuntimesByPaneID.isEmpty)

        let windowKey = "\(UserDefaultsKeys.macWorkspaceRestoration).window.\(fixture.workspaceID.uuidString.lowercased())"
        fixture.defaults.set(Data("{broken-window".utf8), forKey: windowKey)
        let window = MacWorkspaceWindowController(
            request: MacWorkspaceLaunchRequest(
                workspaceID: fixture.workspaceID,
                startsEmpty: false
            ),
            defaults: fixture.defaults
        )
        #expect(window.tabs.count == 1)
        #expect(window.selectedTab.isEmpty)
        #expect(window.selectedTab.localRuntimesByPaneID.isEmpty)
    }

    @Test @MainActor func paneOwnedResourcesSurviveReconstructionAndRetireWithPane() throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let controller = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        let sessionManager = SessionManager(loadImmediately: false)
        let paneID = try #require(controller.focusedPaneID)
        let runtime = try #require(controller.localRuntime(for: paneID))
        let first = try #require(controller.recorder(for: paneID))
        let reconstructed = try #require(controller.recorder(for: paneID))

        #expect(first === reconstructed)
        #expect(controller.localRuntimesByPaneID[paneID] === runtime)
        #expect(controller.recordersByPaneID[paneID] === first)
        controller.removePane(paneID, sessionManager: sessionManager)
        #expect(controller.localRuntime(for: paneID) == nil)
        #expect(controller.recorder(for: paneID) == nil)
        #expect(controller.localRuntimesByPaneID[paneID] == nil)
        #expect(controller.recordersByPaneID[paneID] == nil)
    }

    @Test @MainActor func closedWorkspaceRejectsLateOrNewSSHPreparation() async throws {
        let fixture = try WorkspaceDefaultsFixture()
        defer { fixture.cleanup() }
        let controller = MacWorkspaceController(
            workspaceID: fixture.workspaceID,
            defaults: fixture.defaults
        )
        let sessionManager = SessionManager(loadImmediately: false)
        let settingsManager = SettingsManager(loadImmediately: false)
        let serverID = UUID()
        controller.addPane(intent: .ssh(serverID: serverID), axis: .horizontal)
        let pane = try #require(controller.focusedPane)

        controller.closeAllSessions(sessionManager: sessionManager)
        #expect(controller.isClosed)
        await controller.prepareSSHPaneIfNeeded(
            pane,
            sessionManager: sessionManager,
            settingsManager: settingsManager
        )

        #expect(controller.sessionsByPaneID.isEmpty)
        #expect(controller.loadingPaneIDs.isEmpty)
        #expect(controller.error(for: pane.id) == nil)
    }

    @Test @MainActor func transparencyAndBlurRemainIndependentAtEveryEndpoint() throws {
        let cases: [(
            opacity: Double,
            blur: Double,
            paintsTheme: Bool,
            compositesBlur: Bool,
            fullyTransparent: Bool
        )] = [
            (0, 0, false, false, true),
            (0, 1, false, true, false),
            (1, 0, true, false, false),
            (1, 1, true, true, false)
        ]

        for value in cases {
            let appearance = TerminalGlassAppearance(
                opacity: value.opacity,
                blur: value.blur
            )
            #expect(appearance.opacity == value.opacity)
            #expect(appearance.blur == value.blur)
            #expect(appearance.paintsTheme == value.paintsTheme)
            #expect(appearance.compositesBlur == value.compositesBlur)
            #expect(appearance.isFullyTransparent == value.fullyTransparent)
        }

        #expect(
            TerminalGlassAppearance(opacity: -1, blur: 2)
                == TerminalGlassAppearance(opacity: 0, blur: 1)
        )
        #expect(
            TerminalGlassAppearance(opacity: .nan, blur: .infinity)
                == TerminalGlassAppearance(opacity: 0, blur: 0)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.alphaValue = 0.73
        window.titlebarAppearsTransparent = true
        window.styleMask.remove(.fullSizeContentView)
        let toolbar = NSToolbar(identifier: "sh.glas.test-toolbar")
        window.toolbar = toolbar
        let nativeToolbarStyle = window.toolbarStyle
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "sh.glas.test")
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "sh.glas.test")

        // A clear backing lets canvas opacity and blur vary independently,
        // without changing foreground alpha or native titlebar behavior.
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(window.alphaValue == 0.73)
        #expect(window.tabbingMode == .disallowed)
        #expect(window.tabbingIdentifier.isEmpty)
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.toolbarStyle == nativeToolbarStyle)
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "sh.glas.test", overviewPresented: true)
        let materials = window.contentView?.superview?.subviews.compactMap { $0 as? MacTerminalTitlebarMaterialView } ?? []
        #expect(materials.count == 1)
        #expect(materials.first?.material == .underWindowBackground)
        #expect(materials.first?.isHidden == false)
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "sh.glas.test")
        #expect(materials.first?.material == .sidebar)
    }

    @Test func terminalCanvasAppearancePreservesIncreaseContrast() {
        #expect(
            MacTerminalVisualEffect(amount: 0.5).state
                == .followsWindowActiveState
        )
        #expect(MacTerminalVisualEffect.clampedAmount(-1) == 0)
        #expect(MacTerminalVisualEffect.clampedAmount(0.35) == 0.35)
        #expect(MacTerminalVisualEffect.clampedAmount(2) == 1)
        #expect(MacTerminalVisualEffect.clampedAmount(.nan) == 0)
        #expect(
            MacTerminalVisualEffect.resolvedAppearanceName(
                for: .automatic,
                increaseContrast: false
            ) == nil
        )
        #expect(
            MacTerminalVisualEffect.resolvedAppearanceName(
                for: .automatic,
                increaseContrast: true
            ) == nil
        )
        #expect(
            MacTerminalVisualEffect.resolvedAppearanceName(
                for: .light,
                increaseContrast: false
            ) == .aqua
        )
        #expect(
            MacTerminalVisualEffect.resolvedAppearanceName(
                for: .light,
                increaseContrast: true
            ) == .accessibilityHighContrastAqua
        )
        #expect(
            MacTerminalVisualEffect.resolvedAppearanceName(
                for: .dark,
                increaseContrast: false
            ) == .darkAqua
        )
        #expect(
            MacTerminalVisualEffect.resolvedAppearanceName(
                for: .dark,
                increaseContrast: true
            ) == .accessibilityHighContrastDarkAqua
        )
    }

    @Test @MainActor func workgroupEditorHostsNativeTableWithoutSavingOrShowingAWindow() async throws {
        let preset = LayoutPreset(
            name: "Five terminal tabs",
            sessionIntents: (1...5).map { index in
                LayoutPreset.SessionIntent(kind: .local, label: "Tab \(index)",
                                           startupCommand: "echo \(index)")
            }
        )
        var saves = 0
        let host = NSHostingController(rootView: WorkgroupEditorView(
            context: .edit(preset), servers: [], onSave: { _ in saves += 1 }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 760),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.contentViewController = nil
            window.close()
        }
        window.contentViewController = host
        host.view.setFrameSize(NSSize(width: 800, height: 760))
        func nativeTables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { nativeTables(in: $0) }
        }
        #expect(await waitForCondition(seconds: 3) {
            host.view.layoutSubtreeIfNeeded()
            return nativeTables(in: host.view).contains { $0.numberOfRows == 5 }
        })
        let table = try #require(nativeTables(in: host.view).first { $0.numberOfRows == 5 })
        #expect(table.numberOfColumns == 4)
        let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        let snapshot = FileManager.default.temporaryDirectory.appending(path: "workgroup-editor-controls.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: snapshot)
        print("Workgroup editor render: \(snapshot.path)")
        #expect(!window.isVisible)
        #expect(saves == 0)

        // Construct the staged child editor on the same hidden native surface;
        // merely presenting a draft must not commit or delete anything.
        var deletes = 0
        let child = NSHostingController(rootView: WorkgroupTabEditorView(
            draft: WorkgroupTabDraft(intent: preset.sessionIntents[0]),
            isNew: false, canDelete: true, servers: [],
            onSave: { _ in saves += 1 }, onDelete: { deletes += 1 }
        ))
        window.contentViewController = child
        child.view.layoutSubtreeIfNeeded()
        #expect(child.view.window === window)
        #expect(!window.isVisible)
        #expect(saves == 0)
        #expect(deletes == 0)
    }

    @Test func workgroupTabDraftRoundTripsLocalAndSSHIntentWithoutCrossKindSettings() {
        let local = LayoutPreset.SessionIntent(
            kind: .local, label: "Build", startupCommand: "swift build",
            localShell: "/bin/zsh", localDirectory: "~/Projects"
        )
        let original = WorkgroupTabDraft(intent: local)
        #expect(original.intent == local)
        #expect(original.validationMessage(servers: []) == nil)
        var edited = original
        edited.label = "Changed"
        #expect(original.label == "Build")
        #expect(edited.id == original.id)

        let server = ServerConfiguration(name: "Remote", host: "example.test", username: "tester")
        edited.kind = .ssh
        edited.serverID = server.id
        #expect(edited.validationMessage(servers: [server]) == nil)
        #expect(edited.intent.serverID == server.id)
        #expect(edited.intent.localShell == nil)
        #expect(edited.intent.localDirectory == nil)
        #expect(WorkgroupTabDraft(intent: edited.intent).intent == edited.intent)
        edited.kind = .local
        #expect(edited.intent.serverID == nil)
        #expect(edited.intent.localShell == "/bin/zsh")
    }

    @Test func workgroupTabDraftValidatesConnectionCommandLabelAndLocalPaths() {
        var draft = WorkgroupTabDraft(kind: .ssh)
        #expect(draft.validationMessage(servers: []) != nil)
        draft.serverID = UUID()
        #expect(draft.validationMessage(servers: []) != nil)
        draft.kind = .local
        #expect(draft.validationMessage(servers: []) == nil)
        draft.startupCommand = "echo first\necho second"
        #expect(draft.validationMessage(servers: []) != nil)
        draft.startupCommand = "echo ready"
        draft.label = String(repeating: "x", count: LayoutPreset.SessionIntent.maximumLabelLength + 1)
        #expect(draft.validationMessage(servers: []) != nil)
        draft.label = "Valid"
        draft.localDirectory = "relative/path"
        #expect(draft.validationMessage(servers: []) != nil)
        draft.localDirectory = "~/Projects"
        draft.localShell = "/bin/zsh\0"
        #expect(draft.validationMessage(servers: []) != nil)
        draft.localShell = "/bin/zsh"
        #expect(draft.validationMessage(servers: []) == nil)
    }

    @Test func localTerminalExitPolicyClosesAfterNormalShellExit() {
        #expect(MacLocalTerminalExitPolicy.shouldClose(exitCode: 0))
        #expect(MacLocalTerminalExitPolicy.shouldClose(exitCode: 1))
        #expect(MacLocalTerminalExitPolicy.shouldClose(exitCode: 127))
        #expect(!MacLocalTerminalExitPolicy.shouldClose(exitCode: 128))
        #expect(!MacLocalTerminalExitPolicy.shouldClose(exitCode: 143))
        #expect(!MacLocalTerminalExitPolicy.shouldClose(exitCode: nil))
    }

    @Test @MainActor func localPTYTeardownKillsAndReapsSignalIgnoringShell() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "glas-local-pty-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "trap '' TERM; printf '%d' $$ > \"$1\"; while :; do sleep 1; done",
                "glas-local-pty-test",
                pidFile.path
            ],
            executableName: "sh",
            currentDirectory: FileManager.default.temporaryDirectory.path
        )
        let model = SwiftTermHostModel()
        let processState = SwiftTermLocalProcessState()
        let terminal = SwiftTermLocalProcessHostView(
            model: model,
            processState: processState,
            configuration: configuration,
            theme: SwiftTermTheme(
                fontSize: 13,
                foreground: (1, 1, 1),
                background: (0, 0, 0, 0),
                cursor: (1, 1, 1)
            ),
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: "block",
                blinkingCursor: false,
                scrollbackLines: 100
            )
        )
        var hostingView: NSHostingView<SwiftTermLocalProcessHostView>? = NSHostingView(
            rootView: terminal
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView

        let pidWasWritten = await waitForCondition(seconds: 2) {
            FileManager.default.fileExists(atPath: pidFile.path)
        }
        #expect(pidWasWritten)
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let processID = try #require(pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer {
            if kill(processID, 0) == 0 {
                _ = kill(processID, SIGKILL)
                var status: Int32 = 0
                _ = waitpid(processID, &status, 0)
            }
        }
        #expect(processState.isRunning)

        window.contentView = nil
        hostingView = nil
        window.close()

        let processWasReaped = await waitForCondition(seconds: 4) {
            errno = 0
            let signalResult = kill(processID, 0)
            return signalResult == -1 && errno == ESRCH
        }
        #expect(processWasReaped)
        var status: Int32 = 0
        errno = 0
        #expect(waitpid(processID, &status, WNOHANG) == -1)
        #expect(errno == ECHILD)
        let processIsRunning = processState.isRunning
        #expect(!processIsRunning)
    }

    @Test @MainActor func controllerOwnedLocalPTYSurvivesHostReconstructionUntilExplicitClose()
        async throws
    {
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "glas-retained-local-pty-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "cd /; printf '%d' $$ > \"$1\"; while :; do sleep 1; done",
                "glas-retained-local-pty-test",
                pidFile.path,
            ],
            executableName: "sh",
            currentDirectory: FileManager.default.temporaryDirectory.path
        )
        let runtime = SwiftTermLocalProcessRuntime()
        let theme = SwiftTermTheme(
            fontSize: 13,
            foreground: (1, 1, 1),
            background: (0, 0, 0, 0),
            cursor: (1, 1, 1)
        )
        let settings = SwiftTermRuntimeSettings(
            cursorStyle: "block",
            blinkingCursor: false,
            scrollbackLines: 100
        )
        var hostingView: NSHostingView<SwiftTermLocalProcessHostView>? = NSHostingView(
            rootView: SwiftTermLocalProcessHostView(
                runtime: runtime,
                configuration: configuration,
                theme: theme,
                runtimeSettings: settings
            )
        )
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        #expect(await waitForCondition(seconds: 2) {
            FileManager.default.fileExists(atPath: pidFile.path)
        })
        let pidText = try String(contentsOf: pidFile, encoding: .utf8)
        let processID = try #require(
            pid_t(pidText.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        defer {
            if kill(processID, 0) == 0 {
                _ = kill(processID, SIGKILL)
                var status: Int32 = 0
                _ = waitpid(processID, &status, 0)
            }
        }

        window.contentView = nil
        hostingView = nil
        #expect(runtime.hasEngine)
        #expect(runtime.processState.isRunning)
        // The shell changed directory without emitting OSC 7. Workspace capture
        // must read that directory, not the configured initial directory.
        #expect(runtime.currentWorkingDirectory == "/")
        #expect(runtime.launchedShell == "/bin/sh")
        #expect(kill(processID, 0) == 0)

        hostingView = NSHostingView(
            rootView: SwiftTermLocalProcessHostView(
                runtime: runtime,
                configuration: configuration,
                theme: theme,
                runtimeSettings: settings
            )
        )
        window.contentView = hostingView
        #expect(await waitForCondition(seconds: 1) {
            runtime.processState.isRunning && kill(processID, 0) == 0
        })

        runtime.terminate()
        window.contentView = nil
        hostingView = nil
        window.close()
        #expect(await waitForCondition(seconds: 4) {
            errno = 0
            return kill(processID, 0) == -1 && errno == ESRCH
        })
        #expect(!runtime.hasEngine)
        #expect(!runtime.processState.isRunning)
    }

    @Test @MainActor func headlessLocalRuntimesRunCommandsBeforeTabsArePresented() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "glas-headless-pty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let runtimes = [SwiftTermLocalProcessRuntime(), SwiftTermLocalProcessRuntime()]
        defer {
            runtimes.forEach { $0.terminate() }
            try? FileManager.default.removeItem(at: directory)
        }
        let theme = SwiftTermTheme(
            fontSize: 13,
            foreground: (1, 1, 1),
            background: (0, 0, 0, 0),
            cursor: (1, 1, 1)
        )
        let settings = SwiftTermRuntimeSettings(
            cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100
        )
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/sh", arguments: ["-i"], executableName: "sh",
            currentDirectory: directory.path
        )
        var readyCount = 0
        for (index, runtime) in runtimes.enumerated() {
            runtime.start(
                configuration: configuration, theme: theme, runtimeSettings: settings,
                onProcessReady: {
                    readyCount += 1
                    #expect(runtime.processState.sendCommand(
                        "printf '%s\\n' $$ >> started-\(index); printf 'HEADLESS_READY_\(index)\\n'"
                    ))
                }
            )
            #expect(!runtime.model.allowsFocusOwnership)
        }
        // No hosting view or window exists: both startup commands must already
        // have executed, with their output retained by the owned renderers.
        #expect(await waitForCondition(seconds: 3) {
            runtimes.enumerated().allSatisfy { index, runtime in
                FileManager.default.fileExists(atPath: directory.appending(path: "started-\(index)").path)
                    && runtime.model.getVisibleText().joined().contains("HEADLESS_READY_\(index)")
            }
        })
        let marker = directory.appending(path: "started-0")
        let initialMarker = try String(contentsOf: marker, encoding: .utf8)
        let processID = try #require(pid_t(initialMarker.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(readyCount == 2)
        runtimes[0].start(
            configuration: configuration, theme: theme, runtimeSettings: settings,
            onProcessReady: { readyCount += 1 }
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        var presentedReadyCount = 0
        var presentedOutput = Data()
        var presentedResizeCount = 0
        window.contentView = NSHostingView(rootView: SwiftTermLocalProcessHostView(
            runtime: runtimes[0], configuration: configuration, theme: theme,
            runtimeSettings: settings,
            onOutputData: { presentedOutput.append($0) },
            onResize: { _, _ in presentedResizeCount += 1 },
            onProcessReady: { presentedReadyCount += 1 }
        ))
        #expect(await waitForCondition(seconds: 2) { presentedResizeCount > 0 })
        // Wait for view reconstruction by sending fresh input through the same
        // PTY and checking the presentation's updated output callback.
        #expect(runtimes[0].processState.sendCommand("printf 'ATTACHED_OUTPUT\\n'"))
        #expect(await waitForCondition(seconds: 2) {
            String(decoding: presentedOutput, as: UTF8.self).contains("ATTACHED_OUTPUT")
        })
        #expect(kill(processID, 0) == 0)
        #expect(try String(contentsOf: marker, encoding: .utf8) == initialMarker)
        #expect(runtimes[0].model.getVisibleText().joined().contains("HEADLESS_READY_0"))
        #expect(readyCount == 2)
        #expect(presentedReadyCount == 0)
    }

    @Test @MainActor func localRuntimeDetectsBackgroundJobsAndReportsInheritedExitStatus() async throws {
        let runtime = SwiftTermLocalProcessRuntime()
        defer { runtime.terminate() }
        var terminationCode: Int32?
        var terminated = false
        runtime.start(
            configuration: SwiftTermLocalProcessConfiguration(
                executable: "/bin/sh", arguments: ["-i"], executableName: "sh",
                currentDirectory: FileManager.default.temporaryDirectory.path
            ),
            theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1),
                                 background: (0, 0, 0, 0), cursor: (1, 1, 1)),
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: "block", blinkingCursor: false, scrollbackLines: 100
            ),
            onProcessTerminated: {
                terminationCode = $0
                terminated = true
            }
        )
        #expect(await waitForCondition(seconds: 2) {
            runtime.hasActiveChildProcesses == false
        })
        #expect(runtime.processState.sendCommand("sleep 30 &"))
        #expect(await waitForCondition(seconds: 2) {
            runtime.hasActiveChildProcesses == true
        })
        #expect(runtime.processState.sendCommand("kill -KILL %1; wait; false; exit"))
        try #require(await waitForCondition(seconds: 3) { terminated },
                 "Shell output: \(runtime.model.getVisibleText().joined(separator: "\n"))")
        #expect(terminationCode == 1)
        #expect(MacLocalTerminalExitPolicy.shouldClose(exitCode: terminationCode))
        #expect(!runtime.processState.isRunning)
        #expect(runtime.hasActiveChildProcesses == nil)
    }

    @Test @MainActor func closeWorkspaceTabActionInvokesFocusedHandler() {
        var calls = 0
        let action = MacCloseWorkspaceTabAction { calls += 1 }
        action()
        #expect(calls == 1)
    }

    @Test @MainActor func exitedLocalPTYRestartsInTheExistingTerminal() async throws {
        let configuration = SwiftTermLocalProcessConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 0.1; exit 7"],
            executableName: "sh",
            currentDirectory: FileManager.default.temporaryDirectory.path
        )
        let model = SwiftTermHostModel()
        let processState = SwiftTermLocalProcessState()
        var terminationCount = 0
        var readyCount = 0
        let terminal = SwiftTermLocalProcessHostView(
            model: model,
            processState: processState,
            configuration: configuration,
            theme: SwiftTermTheme(
                fontSize: 13,
                foreground: (1, 1, 1),
                background: (0, 0, 0, 0),
                cursor: (1, 1, 1)
            ),
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: "block",
                blinkingCursor: false,
                scrollbackLines: 100
            ),
            onProcessReady: { readyCount += 1 },
            onProcessTerminated: { _ in terminationCount += 1 }
        )
        var hostingView: NSHostingView<SwiftTermLocalProcessHostView>? = NSHostingView(
            rootView: terminal
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView

        #expect(await waitForCondition(seconds: 3) {
            terminationCount == 1 && processState.exitCode == 7
        })
        #expect(readyCount == 1)
        #expect(processState.restart(configuration))
        #expect(await waitForCondition(seconds: 3) {
            terminationCount == 2 && processState.exitCode == 7
        })
        #expect(readyCount == 2)

        window.contentView = nil
        hostingView = nil
        window.close()
        #expect(!processState.isRunning)
    }

    @Test @MainActor func remoteOSC52IsDeniedAndRecordedOnMac() async {
        let model = SwiftTermHostModel()
        let terminal = SwiftTermHostView(
            model: model,
            theme: SwiftTermTheme(
                fontSize: 13,
                foreground: (1, 1, 1),
                background: (0, 0, 0, 0),
                cursor: (1, 1, 1)
            ),
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: "block",
                blinkingCursor: false,
                scrollbackLines: 100
            ),
            onSendData: { _ in },
            onResize: { _, _ in }
        )
        var hostingView: NSHostingView<SwiftTermHostView>? = NSHostingView(rootView: terminal)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        await Task.yield()

        model.ingest(data: Data("\u{1B}]52;c;SGVs".utf8), nonce: 1)
        model.ingest(data: Data("bG8=\u{07}".utf8), nonce: 2)

        #expect(await waitForCondition(seconds: 2) {
            model.semanticEvents.contains { event in
                guard case .osc52Denied(let decision) = event.kind else { return false }
                return decision.disposition == .deniedWrite
                    && decision.encodedPayloadByteCount == 8
            }
        })

        window.contentView = nil
        hostingView = nil
        window.close()
    }

}

private struct WorkspaceDefaultsFixture {
    let suiteName: String
    let workspaceID = UUID()
    let defaults: UserDefaults

    init() throws {
        suiteName = "sh.glas.mac-workspace-tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    var storageKey: String {
        "\(UserDefaultsKeys.macWorkspaceRestoration).\(workspaceID.uuidString.lowercased())"
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private func replacingTopLevelValue(
    in state: MacWorkspaceRestorationState,
    key: String,
    value: Any
) throws -> MacWorkspaceRestorationState {
    let encoded = try JSONEncoder().encode(state)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object[key] = value
    return try JSONDecoder().decode(
        MacWorkspaceRestorationState.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
}

private func nestedNode(depth: Int) -> MacWorkspaceNode {
    guard depth > 1 else {
        return .pane(MacWorkspacePane(intent: .local))
    }
    return .split(MacWorkspaceSplit(
        axis: depth.isMultiple(of: 2) ? .horizontal : .vertical,
        first: .pane(MacWorkspacePane(intent: .local)),
        second: nestedNode(depth: depth - 1)
    ))
}

private func balancedNode(paneCount: Int) -> MacWorkspaceNode {
    guard paneCount > 1 else {
        return .pane(MacWorkspacePane(intent: .local))
    }
    let firstCount = paneCount / 2
    return .split(MacWorkspaceSplit(
        axis: paneCount.isMultiple(of: 2) ? .horizontal : .vertical,
        first: balancedNode(paneCount: firstCount),
        second: balancedNode(paneCount: paneCount - firstCount)
    ))
}

@MainActor
private func waitForCondition(
    seconds: Double,
    condition: () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(seconds))
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
#endif

#endif
