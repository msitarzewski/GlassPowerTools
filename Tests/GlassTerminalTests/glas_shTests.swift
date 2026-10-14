//
//  glas_shTests.swift
//  glas.shTests
//
//  Created by Michael Sitarzewski on 9/10/25.
//

import Testing
import Foundation
@testable import GlassTerminal
import GlassLayers
import GlasSecretStore
import GlassConnectionUI
import NIOCore
import NIOSSH
import Citadel
import GlassEditorCore
import GlassTerminalEmulator
import SwiftUI
import GlassShell
import UniformTypeIdentifiers
#if canImport(UIKit)
import Combine
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if os(macOS)
@Suite(.serialized)
struct MacTerminalWindowPolicyTests {
    @Test @MainActor func titlebarMaterialIsPassiveAndInstalledOnce() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = try #require(window.contentView?.superview)
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "test")
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "test")
        root.layoutSubtreeIfNeeded()
        let materials = root.subviews.compactMap { $0 as? MacTerminalTitlebarMaterialView }
        #expect(materials.count == 1)
        let material = try #require(materials.first)
        #expect(material.hitTest(NSPoint(x: material.bounds.midX, y: material.bounds.midY)) == nil)
        #expect(material.material == .sidebar)
        #expect(material.blendingMode == .behindWindow)
        #expect(material.state == .followsWindowActiveState)
        #expect(material.alphaValue == 1)
        #expect(root.subviews.first === material)
        #expect(material.frame.height > 0)
        #expect(abs(material.frame.minY - window.contentLayoutRect.maxY) < 1)
        #expect(!window.isVisible)
    }
    @Test @MainActor func connectionSubtitleOnlyFlagsNonHealthyStates() {
        let address = "user@host:22"
        #expect(MacWorkspaceController.connectionSubtitle(address, state: .connected) == address)
        #expect(MacWorkspaceController.connectionSubtitle(address, state: nil) == address)
        #expect(MacWorkspaceController.connectionSubtitle(address, state: .connecting) == "user@host:22 — Connecting…")
        #expect(MacWorkspaceController.connectionSubtitle(address, state: .reconnecting) == "user@host:22 — Reconnecting…")
        #expect(MacWorkspaceController.connectionSubtitle(address, state: .disconnected) == "user@host:22 — Disconnected")
        #expect(MacWorkspaceController.connectionSubtitle(address, state: .error("details")) == "user@host:22 — Connection failed")
    }
    @Test @MainActor func workspaceUsesNativeTitle() async throws {
        let manager = SessionManager(loadImmediately: false)
        let settings = SettingsManager(loadImmediately: false)
        let view = MacWorkspaceView(request: MacWorkspaceLaunchRequest(startsEmpty: true))
            .environment(manager).environment(settings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        defer { window.contentViewController = nil }
        for _ in 0..<8 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(window.title == "New Terminal")
        #expect(window.isMovable)
        let toolbar = try #require(window.toolbar)
        func sidebarController(_ view: NSView) -> NSSplitViewController? {
            if let split = view as? NSSplitView,
               let controller = split.delegate as? NSSplitViewController,
               controller.splitViewItems.contains(where: { $0.behavior == .sidebar }) { return controller }
            return view.subviews.lazy.compactMap { sidebarController($0) }.first
        }
        let root = try #require(window.contentView)
        let split = try #require(sidebarController(root))
        let sidebar = try #require(split.splitViewItems.first { $0.behavior == .sidebar })
        sidebar.isCollapsed = true
        for _ in 0..<8 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        // **The family's sidebar arrangement**, as glassdb and glas.sh have always had it:
        // AppKit's own toggle over the sidebar, the tracking separator at the column divider, and
        // the app's add button leading the content region beyond it.
        //
        // This test used to pin the opposite — an app-supplied "sidebar-toggle" ahead of the
        // separator — and that arrangement kept regressing in use. A placed button is an ordinary
        // toolbar item: it drops into the overflow menu with its title once the toolbar is
        // crowded, and it disappears with the sidebar region when the column collapses. AppKit's
        // item does neither. `glassdb/Constants.swift:267-273` removes the system toggle on every
        // platform *except* macOS for exactly this reason.
        let sidebarIndices = toolbar.items.indices.filter {
            toolbar.items[$0].itemIdentifier.rawValue.contains("toggleSidebar")
        }
        #expect(sidebarIndices.count == 1, "the system toggle, exactly once — not replaced")
        let sidebarIndex = try #require(sidebarIndices.first)
        let newTabIndex = try #require(toolbar.items.firstIndex {
            $0.itemIdentifier.rawValue == "new-terminal-tab"
        })
        let save = try #require(toolbar.items.first {
            $0.itemIdentifier.rawValue == "save-workspace"
        })
        let separatorIndex = try #require(toolbar.items.firstIndex { $0 is NSTrackingSeparatorToolbarItem })
        #expect(sidebarIndex < separatorIndex, "the toggle belongs to the sidebar region")
        #expect(separatorIndex < newTabIndex, "New Tab leads the content region, past the divider")
        // The toggle is the sidebar region's only control: anything else placed there vanishes
        // with the column when it collapses, which is the state this test has just put it in.
        let sidebarControls = toolbar.items.prefix(separatorIndex).filter {
            $0.itemIdentifier != .flexibleSpace && $0.itemIdentifier != .space
        }
        #expect(sidebarControls.count == 1)
        let itemIDs = toolbar.items.map(\.itemIdentifier)
        // Window updates no longer remove or replace any toolbar items.
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        #expect(toolbar.items.map(\.itemIdentifier) == itemIDs)
        for width in [1180.0, 900.0, 720.0] {
            window.setContentSize(NSSize(width: width, height: 760))
            window.contentView?.layoutSubtreeIfNeeded()
            #expect(toolbar.visibleItems?.contains {
                let id = $0.itemIdentifier.rawValue
                return (id.contains("toggleSidebar") || id == "sidebar-toggle") && !$0.isHidden
            } == true)
            #expect(toolbar.visibleItems?.contains {
                $0.itemIdentifier.rawValue == "new-terminal-tab" && !$0.isHidden
            } == true)
        }
        split.toggleSidebar(nil)
        #expect(!sidebar.isCollapsed)
        let frameView = try #require(root.superview)
        let material = try #require(frameView.subviews.compactMap { $0 as? MacTerminalTitlebarMaterialView }.first)
        let sidebarView = sidebar.viewController.view
        material.followSidebarBoundary()
        for width in [1180.0, 900.0] {
            window.setContentSize(NSSize(width: width, height: 760))
            for _ in 0..<12 {
                frameView.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(25))
            }
            let sidebarEdge = sidebarView.convert(sidebarView.bounds, to: frameView).maxX
            #expect(sidebarView.convert(sidebarView.bounds, to: frameView).minX >= -1)
            #expect(sidebarEdge > 0)
            #expect(abs(material.frame.minX - sidebarEdge) < 1)
            #expect(toolbar.visibleItems?.contains {
                let id = $0.itemIdentifier.rawValue
                return (id.contains("toggleSidebar") || id == "sidebar-toggle") && !$0.isHidden
            } == true)
        }
        split.toggleSidebar(nil)
        #expect(sidebar.isCollapsed)
        for _ in 0..<12 {
            frameView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(abs(material.frame.minX - frameView.bounds.minX) < 1)
        if #available(macOS 26.1, *) {
            #expect(toolbar.items[sidebarIndex].visibilityPriority.rawValue > save.visibilityPriority.rawValue)
            #expect(toolbar.items[newTabIndex].visibilityPriority.rawValue > save.visibilityPriority.rawValue)
        }
        #expect(window.toolbar?.items.contains(where: {
            $0.itemIdentifier.rawValue.contains("workspace-drag-title")
        }) != true)
        #expect(!window.isVisible)
    }

    @Test @MainActor func terminalWindowPolicyPreservesNativeChrome() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let styleMask = window.styleMask
        let toolbarStyle = window.toolbarStyle
        window.alphaValue = 0.87
        window.titlebarAppearsTransparent = false
        let backgroundDragging = window.isMovableByWindowBackground
        MacTerminalWindowPolicy.apply(window, tabbingIdentifier: "test")
        #expect(window.isMovable)
        #expect(window.isMovableByWindowBackground == backgroundDragging)
        #expect(window.styleMask == styleMask)
        #expect(window.toolbarStyle == toolbarStyle)
        #expect(window.backgroundColor == .clear)
        #expect(!window.isOpaque)
        #expect(window.alphaValue == 0.87)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.tabbingMode == .disallowed)
        #expect(!window.isVisible)
    }

    @Test @MainActor func nativeTabSidebarOpensOnceAndRespectsUserToggle() async throws {
        let tabs = TabView {
            Tab("Local", systemImage: "terminal") { Text("Local shell") }
            Tab("Remote", systemImage: "server.rack") { Text("Remote shell") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(width: 900, height: 600)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: tabs)
        defer { window.contentViewController = nil }
        func nativeSidebar(_ view: NSView) -> NSSplitViewItem? {
            if let split = view as? NSSplitView,
               let owner = split.delegate as? NSSplitViewController,
               let sidebar = owner.splitViewItems.first(where: { $0.behavior == .sidebar }) { return sidebar }
            return view.subviews.lazy.compactMap { nativeSidebar($0) }.first
        }
        let root = try #require(window.contentView)
        var discovered: NSSplitViewItem?
        for _ in 0..<20 {
            root.layoutSubtreeIfNeeded()
            discovered = nativeSidebar(root)
            if discovered != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let sidebar = try #require(discovered)
        sidebar.isCollapsed = true
        let coordinator = MacTerminalWindowReader.Coordinator()
        coordinator.configureInitialSidebar(in: window, enabled: true)
        #expect(!sidebar.isCollapsed)
        sidebar.isCollapsed = true
        coordinator.configureInitialSidebar(in: window, enabled: true)
        #expect(sidebar.isCollapsed)
        let ordinary = MacTerminalWindowReader.Coordinator()
        ordinary.configureInitialSidebar(in: window, enabled: false)
        #expect(sidebar.isCollapsed)
        #expect(!window.isVisible)
    }
}
#endif

private struct LegacyKEXFixture: Error, CustomStringConvertible {
    var description: String { "keyExchangeNegotiationFailure" }
}

private struct TestByteSequence: AsyncSequence, Sendable {
    typealias Element = UInt8

    let count: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        let count: Int
        var index = 0

        mutating func next() async -> UInt8? {
            guard index < count else { return nil }
            defer { index += 1 }
            return UInt8(truncatingIfNeeded: index)
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(count: count)
    }
}

@MainActor
private final class TerminalWriteProbe {
    private(set) var writes: [Data] = []

    func receive(_ data: Data) async throws {
        if writes.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        writes.append(data)
    }
}

@MainActor
private final class TerminalResizeProbe {
    private(set) var resizes: [String] = []

    func receive(rows: Int, columns: Int) async throws {
        resizes.append("\(rows)x\(columns)")
        if resizes.count == 1 {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class FakeICloudSettingsStore: ICloudSettingsKeyValueStore {
    var isAvailable = true
    var isAccountAvailable = true
    var synchronizeResult = true
    var suspendsSynchronization = false
    private(set) var values: [String: Data] = [:]
    private(set) var setCount = 0
    private(set) var synchronizeCount = 0
    private(set) var observerCount = 0
    private var pendingSynchronizations: [CheckedContinuation<Bool, Never>] = []
    private var handler: (@MainActor @Sendable (ICloudSettingsStoreChange) -> Void)?

    var pendingSynchronizationCount: Int { pendingSynchronizations.count }

    func data(forKey key: String) -> Data? { values[key] }

    func set(_ data: Data, forKey key: String) {
        values[key] = data
        setCount += 1
    }

    func synchronize() async -> Bool {
        synchronizeCount += 1
        guard suspendsSynchronization else { return synchronizeResult }
        return await withCheckedContinuation { continuation in
            pendingSynchronizations.append(continuation)
        }
    }

    func resumeNextSynchronization(returning result: Bool) {
        precondition(!pendingSynchronizations.isEmpty)
        pendingSynchronizations.removeFirst().resume(returning: result)
    }

    func observeExternalChanges(
        _ handler: @escaping @MainActor @Sendable (ICloudSettingsStoreChange) -> Void
    ) -> NSObjectProtocol {
        self.handler = handler
        observerCount += 1
        return NSObject()
    }

    func removeExternalChangeObserver(_ observer: NSObjectProtocol) {
        handler = nil
        observerCount = max(0, observerCount - 1)
    }

    func emit(_ change: ICloudSettingsStoreChange) {
        handler?(change)
    }
}

@MainActor
private final class ServerPasswordProbe {
    var values: [UUID: String] = [:]
    var retrieveError: Error?
    var saveError: Error?
    var deleteError: Error?

    var store: ServerPasswordStore {
        ServerPasswordStore(
            retrieve: { [unowned self] server in
                if let retrieveError { throw retrieveError }
                guard let value = values[server.id] else { throw SecretStoreError.notFound }
                return value
            },
            save: { [unowned self] password, server in
                if let saveError { throw saveError }
                values[server.id] = password
            },
            delete: { [unowned self] serverID in
                if let deleteError { throw deleteError }
                guard values.removeValue(forKey: serverID) != nil else {
                    throw SecretStoreError.notFound
                }
            }
        )
    }
}

@MainActor
private final class SharedServerCredentialProbe {
    var values: [String: Data] = [:]
    var failSaveKey: String?

    func key(account: String, service: String) -> String {
        "\(service)\u{0}\(account)"
    }

    var store: ServerCredentialStore {
        ServerCredentialStore(
            read: { [unowned self] account, service in
                values[key(account: account, service: service)]
            },
            save: { [unowned self] data, account, service in
                let storageKey = key(account: account, service: service)
                if failSaveKey == storageKey {
                    failSaveKey = nil
                    throw TerminalWriteFailure()
                }
                values[storageKey] = data
            },
            addIfAbsent: { [unowned self] data, account, service in
                let storageKey = key(account: account, service: service)
                guard values[storageKey] == nil else { return false }
                values[storageKey] = data
                return true
            },
            delete: { [unowned self] account, service in
                values.removeValue(forKey: key(account: account, service: service))
            }
        )
    }

    var passwordStore: ServerPasswordStore {
        ServerPasswordStore(
            retrieve: { [unowned self] server in
                try KeychainManager.retrievePassword(for: server, store: store)
            },
            save: { [unowned self] password, server in
                try KeychainManager.savePassword(password, for: server, store: store)
            },
            delete: { [unowned self] serverID in
                try KeychainManager.deletePassword(
                    for: ServerPasswordStore.passwordReference(for: serverID),
                    store: store
                )
            },
            deletePublished: { [unowned self] server in
                try KeychainManager.deletePublishedPassword(for: server, store: store)
            },
            deleteSharedCompatibility: { [unowned self] server in
                try KeychainManager.deleteSharedCompatibilityPassword(
                    for: server,
                    store: store
                )
            },
            prepareRollback: { [unowned self] server in
                try KeychainManager.passwordRollback(for: server, store: store)
            }
        )
    }
}

private struct TerminalWriteFailure: Error {}

private enum HostTrustStoreProbeError: Error {
    case injectedFailure
}

private func syntheticOpenSSHPrivateKey(from encodedKey: ByteBuffer) -> String {
    let privateKeyLabel = "PRIVATE" + " KEY"
    return [
        "-----BEGIN OPENSSH \(privateKeyLabel)-----",
        Data(encodedKey.readableBytesView).base64EncodedString(),
        "-----END OPENSSH \(privateKeyLabel)-----",
    ].joined(separator: "\n")
}

private enum CredentialMigrationProbeError: Error {
    case queryFailure
    case persistenceFailure
}

@MainActor
private final class CredentialMigrationProbe {
    var values: [String: Data] = [:]
    var report: CredentialMigrationReport?
    var version = 0
    var failReadAccounts = Set<String>()
    var omitReadbackAccounts = Set<String>()
    var failDeleteAccounts = Set<String>()
    var failDeleteAfterMutationAccounts = Set<String>()
    var failWriteAfterMutationAccounts = Set<String>()
    var replaceAccountBeforeNextAdd: (account: String, data: Data)?
    var replaceAccountOnNextReportSave: (account: String, data: Data)?
    var replaceAccountOnNextCompletedReportSave: (account: String, data: Data)?
    var failReportSave = false
    var writeCount = 0
    var deleteCount = 0

    var store: CredentialMigrationStore {
        CredentialMigrationStore(
            read: { [self] account in
                if failReadAccounts.contains(account) {
                    throw CredentialMigrationProbeError.queryFailure
                }
                if omitReadbackAccounts.contains(account), values[account] != nil {
                    return nil
                }
                return values[account]
            },
            addIfAbsent: { [self] data, account in
                writeCount += 1
                if let replacement = replaceAccountBeforeNextAdd,
                   replacement.account == account {
                    replaceAccountBeforeNextAdd = nil
                    values[account] = replacement.data
                }
                guard values[account] == nil else { return false }
                values[account] = data
                if failWriteAfterMutationAccounts.contains(account) {
                    throw CredentialMigrationProbeError.queryFailure
                }
                return true
            },
            loadReport: { [self] in report },
            saveReport: { [self] value in
                if value.state == .completed,
                   let replacement = replaceAccountOnNextCompletedReportSave {
                    replaceAccountOnNextCompletedReportSave = nil
                    values[replacement.account] = replacement.data
                    throw CredentialMigrationProbeError.persistenceFailure
                }
                if let replacement = replaceAccountOnNextReportSave {
                    replaceAccountOnNextReportSave = nil
                    values[replacement.account] = replacement.data
                    throw CredentialMigrationProbeError.persistenceFailure
                }
                if failReportSave {
                    throw CredentialMigrationProbeError.persistenceFailure
                }
                report = value
            },
            removeReport: { [self] in report = nil },
            loadVersion: { [self] in version },
            saveVersion: { [self] value in version = value }
        )
    }

    var oauthStore: TailscaleOAuthCredentialStore {
        return TailscaleOAuthCredentialStore(
            read: { [self] account in
                if failReadAccounts.contains(account) {
                    throw CredentialMigrationProbeError.queryFailure
                }
                return values[account]
            },
            addIfAbsent: { [self] data, account in
                writeCount += 1
                if let replacement = replaceAccountBeforeNextAdd,
                   replacement.account == account {
                    replaceAccountBeforeNextAdd = nil
                    values[account] = replacement.data
                }
                guard values[account] == nil else { return false }
                values[account] = data
                return true
            },
            delete: { [self] account in
                deleteCount += 1
                if failDeleteAccounts.contains(account) {
                    throw CredentialMigrationProbeError.queryFailure
                }
                values.removeValue(forKey: account)
                if failDeleteAfterMutationAccounts.contains(account) {
                    throw CredentialMigrationProbeError.queryFailure
                }
            }
        )
    }
}

@MainActor
private final class HostTrustStoreProbe {
    var records: [String: PinnedSSHHostKey] = [:]
    var saveCount = 0
    var allRecordsCount = 0
    var failSaves = false
    var omitRecordsOnReadback = false

    var store: HostTrustMigrationStore {
        HostTrustMigrationStore(
            save: { [self] record in
                saveCount += 1
                if failSaves {
                    throw HostTrustStoreProbeError.injectedFailure
                }
                records[record.storageAccount] = record
            },
            allRecords: { [self] in
                allRecordsCount += 1
                return omitRecordsOnReadback ? [] : Array(records.values)
            }
        )
    }
}

@MainActor
struct glas_shTests {
    @Test @MainActor func localSSHSubstitutionIsDeviceLocalAndInvalidatedWhenSourceChanges() throws {
        let suite = "ssh-substitution-\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        let source = LayoutPreset.SessionIntent(kind: .local, label: "Build", startupCommand: "pwd", localDirectory: "/Mac/project")
        var preset = LayoutPreset(name: "Project", sessionIntents: [source])
        let replacement = WorkgroupSSHSubstitution(source: source, serverID: UUID(), directory: "/srv/it's a project", command: "pwd")
        settings.saveSSHSubstitutions([0: replacement], for: preset)
        #expect(settings.sshSubstitutions(for: preset)[0] == replacement)
        #expect(preset.sessionIntents[0] == source)
        #expect(replacement.intent.kind == .ssh)
        #expect(replacement.intent.localShell == nil)
        // Single line: the ticket rejects newlines (the PTY would run them as separate commands).
        #expect(replacement.intent.startupCommand == "cd -- '/srv/it'\\''s a project' && { pwd; }")
        preset.sessionIntents[0].label = "Changed recipe"
        #expect(settings.sshSubstitutions(for: preset).isEmpty)
    }

    @Test func sshSubstitutionStartupCommandIsAlwaysASingleLineTheTicketAccepts() {
        let source = LayoutPreset.SessionIntent(kind: .local, label: "Build", startupCommand: "pwd")
        let trailingSemicolon = WorkgroupSSHSubstitution(source: source, serverID: UUID(), directory: "/srv/app", command: "make;")
        #expect(trailingSemicolon.intent.startupCommand == "cd -- '/srv/app' && { make; }")
        let background = WorkgroupSSHSubstitution(source: source, serverID: UUID(), directory: "/srv/app", command: "tail -f log &")
        #expect(background.intent.startupCommand == "cd -- '/srv/app' && { tail -f log & }")
        let directoryOnly = WorkgroupSSHSubstitution(source: source, serverID: UUID(), directory: "/srv/app", command: "  ")
        #expect(directoryOnly.intent.startupCommand == "cd -- '/srv/app'")
        let commandOnly = WorkgroupSSHSubstitution(source: source, serverID: UUID(), directory: "", command: "pwd")
        #expect(commandOnly.intent.startupCommand == "pwd")
        for candidate in [trailingSemicolon, background, directoryOnly, commandOnly] {
            #expect(TerminalStartupCommandTicket(command: candidate.intent.startupCommand) != nil)
        }
    }

    @Test func codableColorResolvesExplicitSRGBComponents() {
        let color = CodableColor(color: Color(
            .sRGB,
            red: 0.125,
            green: 0.375,
            blue: 0.625,
            opacity: 0.75
        ))

        #expect(abs(color.red - 0.125) < 0.000_001)
        #expect(abs(color.green - 0.375) < 0.000_001)
        #expect(abs(color.blue - 0.625) < 0.000_001)
        #expect(abs(color.alpha - 0.75) < 0.000_001)

        let semanticRed = CodableColor(color: .red)
        #expect(semanticRed.red > 0.9)
        #expect(semanticRed.red > semanticRed.green)
        #expect(semanticRed.red > semanticRed.blue)

        let translucentBlue = CodableColor(color: Color.blue.opacity(0.3))
        #expect(translucentBlue.blue > 0.9)
        #expect(abs(translucentBlue.alpha - 0.3) < 0.000_001)
    }

    @Test func defaultThemeUsesMacOS27ClearDarkPaletteWithoutBackgroundCoupling() {
        let theme = TerminalTheme.default
        let expectedForeground = CodableColor(
            sRGBRed: 0.901596844196,
            green: 0.901596844196,
            blue: 0.901596844196
        )
        let expectedSelection = CodableColor(
            sRGBRed: 0.200930923223,
            green: 0.304736882448,
            blue: 0.370029002428
        )
        let expectedANSIColors = [
            CodableColor(sRGBRed: 0.208221729000, green: 0.258872947300, blue: 0.296137570100),
            CodableColor(sRGBRed: 0.705090082900, green: 0.335715730100, blue: 0.281149064300),
            CodableColor(sRGBRed: 0.424156630500, green: 0.667281834600, blue: 0.441522716500),
            CodableColor(sRGBRed: 0.768627451000, green: 0.674509803900, blue: 0.384313725500),
            CodableColor(sRGBRed: 0.427450980400, green: 0.588235294100, blue: 0.705882352900),
            CodableColor(sRGBRed: 0.741176470600, green: 0.482352941200, blue: 0.803921568600),
            CodableColor(sRGBRed: 0.484715120500, green: 0.795007090900, blue: 0.805706814000),
            CodableColor(sRGBRed: 0.868783575500, green: 0.899543531400, blue: 0.922173947700),
            CodableColor(sRGBRed: 0.276332894900, green: 0.362595777900, blue: 0.426060269100),
            CodableColor(sRGBRed: 0.876132015300, green: 0.424238529000, blue: 0.352688727000),
            CodableColor(sRGBRed: 0.474204848200, green: 0.743332020300, blue: 0.492389116600),
            CodableColor(sRGBRed: 0.898039215700, green: 0.784313725500, blue: 0.447058823500),
            CodableColor(sRGBRed: 0.403921568600, green: 0.709803921600, blue: 0.929411764700),
            CodableColor(sRGBRed: 0.827450980400, green: 0.537254902000, blue: 0.898039215700),
            CodableColor(sRGBRed: 0.517774366200, green: 0.867731615800, blue: 0.879799107100),
            CodableColor(sRGBRed: 0.899579140100, green: 0.935473975100, blue: 0.961882174700),
        ]

        #expect(theme.foreground == expectedForeground)
        #expect(theme.cursor == expectedForeground)
        #expect(theme.selection == expectedSelection)
        #expect(theme.ansiColors == expectedANSIColors)
        #expect(theme.background == CodableColor(
            sRGBRed: 0,
            green: 0,
            blue: 0,
            alpha: 0.3
        ))

        let uniqueColors = theme.ansiColors.reduce(into: [CodableColor]()) { result, color in
            if !result.contains(color) { result.append(color) }
        }
        #expect(uniqueColors.count == 16)
    }

    @Test func terminalThemeRoundTripsEveryClearDarkColor() throws {
        let encoded = try JSONEncoder().encode(TerminalTheme.default)
        let decoded = try JSONDecoder().decode(TerminalTheme.self, from: encoded)

        #expect(decoded == TerminalTheme.default)
        #expect(decoded.ansiColors.count == 16)
        #expect(decoded.resolvedAppearance == .dark)
        #expect(decoded.canvasBackgroundColor.alpha == 1)
        #expect(decoded.swiftTermTheme.background.alpha == 0)
    }

    @Test func swiftTermThemePreservesForegroundAndANSISources() {
        var theme = TerminalTheme.default
        theme.foreground = CodableColor(sRGBRed: 0.123, green: 0.456, blue: 0.789)
        let sourceANSI = (0..<16).map { index in
            let value = Double(index + 1) / 17
            return CodableColor(
                sRGBRed: value,
                green: 1 - value,
                blue: value / 2,
                alpha: 0.25
            )
        }
        theme.black = sourceANSI[0]
        theme.red = sourceANSI[1]
        theme.green = sourceANSI[2]
        theme.yellow = sourceANSI[3]
        theme.blue = sourceANSI[4]
        theme.magenta = sourceANSI[5]
        theme.cyan = sourceANSI[6]
        theme.white = sourceANSI[7]
        theme.brightBlack = sourceANSI[8]
        theme.brightRed = sourceANSI[9]
        theme.brightGreen = sourceANSI[10]
        theme.brightYellow = sourceANSI[11]
        theme.brightBlue = sourceANSI[12]
        theme.brightMagenta = sourceANSI[13]
        theme.brightCyan = sourceANSI[14]
        theme.brightWhite = sourceANSI[15]

        let swiftTermTheme = theme.swiftTermTheme

        #expect(swiftTermTheme.foreground.red == theme.foreground.red)
        #expect(swiftTermTheme.foreground.green == theme.foreground.green)
        #expect(swiftTermTheme.foreground.blue == theme.foreground.blue)
        #expect(swiftTermTheme.background.alpha == 0)
        #expect(swiftTermTheme.ansiColors == sourceANSI.map {
            SwiftTermThemeColor(red: $0.red, green: $0.green, blue: $0.blue)
        })
    }

    @Test func legacyThemeWithoutAppearanceDerivesStableCanvasPolarity() throws {
        let encoded = try JSONEncoder().encode(TerminalTheme.default)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "preferredAppearance")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TerminalTheme.self, from: legacyData)

        #expect(decoded.preferredAppearance == nil)
        #expect(decoded.resolvedAppearance == .dark)

        var light = decoded
        light.background = CodableColor(sRGBRed: 0.9, green: 0.9, blue: 0.9, alpha: 0.1)
        #expect(light.resolvedAppearance == .light)
        #expect(light.canvasBackgroundColor.alpha == 1)

        var automaticDark = decoded
        automaticDark.preferredAppearance = .automatic
        #expect(automaticDark.resolvedAppearance == .dark)

        var automaticLight = light
        automaticLight.preferredAppearance = .automatic
        #expect(automaticLight.resolvedAppearance == .light)

        var explicitLight = decoded
        explicitLight.preferredAppearance = .light
        #expect(explicitLight.resolvedAppearance == .light)

        var explicitDark = light
        explicitDark.preferredAppearance = .dark
        #expect(explicitDark.resolvedAppearance == .dark)
    }

    @Test func applyingClearDarkColorsPreservesThemeIdentityBackgroundAndFont() {
        let id = UUID()
        let background = CodableColor(sRGBRed: 0.12, green: 0.23, blue: 0.34, alpha: 0.45)
        var theme = makeCorruptedLegacyGlassTheme(
            id: id,
            background: background,
            fontName: "Menlo",
            fontSize: 17
        )
        theme.preferredAppearance = .light

        theme.applyAppleClearDarkColors()

        #expect(theme.id == id)
        #expect(theme.name == "Glass Terminal")
        #expect(theme.background == background)
        #expect(theme.fontName == "Menlo")
        #expect(theme.fontSize == 17)
        #expect(theme.preferredAppearance == .dark)
        #expect(theme.resolvedAppearance == .dark)
        #expect(theme.foreground == TerminalTheme.appleClearDarkForeground)
        #expect(theme.selection == TerminalTheme.appleClearDarkSelection)
        #expect(theme.ansiColors == TerminalTheme.appleClearDarkANSIColors)
    }

    @Test func settingsManagerMigratesOnlyExactCorruptedGlassColorsAndPersistsRepair() throws {
        let suiteName = "sh.glas.test.theme-migration.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let id = UUID()
        let background = CodableColor(sRGBRed: 0.15, green: 0.25, blue: 0.35, alpha: 0.45)
        let legacy = makeCorruptedLegacyGlassTheme(
            id: id,
            background: background,
            fontName: "Menlo",
            fontSize: 18
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: UserDefaultsKeys.theme)
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)

        settings.loadTheme()

        #expect(settings.currentTheme.id == TerminalTheme.defaultID)
        #expect(settings.currentTheme.name == legacy.name)
        #expect(settings.currentTheme.background == background)
        #expect(settings.currentTheme.fontName == "Menlo")
        #expect(settings.currentTheme.fontSize == 18)
        #expect(settings.currentTheme.foreground == TerminalTheme.appleClearDarkForeground)
        #expect(settings.currentTheme.selection == TerminalTheme.appleClearDarkSelection)
        #expect(settings.currentTheme.ansiColors == TerminalTheme.appleClearDarkANSIColors)
        let persistedData = try #require(defaults.data(forKey: UserDefaultsKeys.theme))
        let persisted = try JSONDecoder().decode(TerminalTheme.self, from: persistedData)
        #expect(persisted == settings.currentTheme)
    }

    @Test func settingsManagerPreservesCustomizedLegacyNamedTheme() throws {
        let suiteName = "sh.glas.test.theme-custom.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var custom = makeCorruptedLegacyGlassTheme()
        custom.red = CodableColor(sRGBRed: 0.9, green: 0.1, blue: 0.2)
        defaults.set(try JSONEncoder().encode(custom), forKey: UserDefaultsKeys.theme)
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)

        settings.loadTheme()

        let expected = custom.reidentified(id: TerminalTheme.defaultID)
        #expect(settings.currentTheme == expected)
        let persistedData = try #require(defaults.data(forKey: UserDefaultsKeys.theme))
        #expect(try JSONDecoder().decode(TerminalTheme.self, from: persistedData) == expected)
    }

    @Test func settingsManagerMigratesSingleThemeIntoVersionedLibrary() throws {
        let suiteName = "sh.glas.test.theme-library-migration.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = TerminalTheme.default.reidentified(name: "Existing Theme")
        defaults.set(try JSONEncoder().encode(legacy), forKey: UserDefaultsKeys.theme)
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)

        settings.loadTheme()

        #expect(settings.currentTheme.name == legacy.name)
        #expect(settings.currentTheme.id == TerminalTheme.defaultID)
        #expect(settings.themeLibrary.selectedThemeID == TerminalTheme.defaultID)
        #expect(settings.themeLibrary.activeRecords.count == 1)
        #expect(settings.themeLibrary.activeRecords.first?.origin == .builtIn)
        let data = try #require(defaults.data(forKey: UserDefaultsKeys.themeLibrary))
        let persisted = try JSONDecoder().decode(TerminalThemeLibrary.self, from: data)
        #expect(persisted.selectedTheme?.name == legacy.name)
        #expect(persisted.selectedTheme?.id == TerminalTheme.defaultID)
    }

    /// The built-in theme's identifier changed on 2026-09-27. A library saved under the old one
    /// loads under the new one, stays selected, and is saved that way once.
    @Test func builtInThemeLegacyIdentifierIsRewrittenAndSaved() throws {
        let suiteName = "sh.glas.test.theme-legacy-id.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyBuiltIn = TerminalTheme.default.reidentified(id: TerminalTheme.legacyDefaultID)
        let custom = TerminalTheme.default.reidentified(id: UUID(), name: "Mine")
        var saved = TerminalThemeLibrary.initial()
        saved.records = [
            TerminalThemeRecord(theme: legacyBuiltIn, origin: .builtIn, modifiedAt: .distantPast, deletedAt: nil),
            TerminalThemeRecord(theme: custom, origin: .appleTerminal, modifiedAt: .distantPast, deletedAt: nil),
        ]
        saved.selectedThemeID = TerminalTheme.legacyDefaultID
        defaults.set(try JSONEncoder().encode(saved), forKey: UserDefaultsKeys.themeLibrary)
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)

        settings.loadTheme()

        #expect(settings.themeLibrary.selectedThemeID == TerminalTheme.defaultID)
        #expect(settings.currentTheme.id == TerminalTheme.defaultID)
        #expect(Set(settings.themeLibrary.activeRecords.map(\.id)) == [TerminalTheme.defaultID, custom.id])
        let data = try #require(defaults.data(forKey: UserDefaultsKeys.themeLibrary))
        let persisted = try JSONDecoder().decode(TerminalThemeLibrary.self, from: data)
        #expect(!persisted.records.contains { $0.id == TerminalTheme.legacyDefaultID }, "saved rewritten")
        #expect(persisted.selectedThemeID == TerminalTheme.defaultID)
    }

    /// A device still on an older build syncs the built-in theme under its old identifier; that is
    /// accepted and merged as the one built-in theme, while any other identifier stays refused.
    @Test func syncedBuiltInThemeUnderLegacyIdentifierIsAccepted() throws {
        let now = Date()
        var payload = makeICloudPayload(customID: UUID(), customDeletedAt: nil, modifiedAt: now)
        let legacy = TerminalTheme.default.reidentified(id: TerminalTheme.legacyDefaultID)
        payload.themeRecords[0] = ICloudTerminalThemeRecord(
            theme: makeICloudTheme(legacy), origin: .builtIn, modifiedAt: now, deletedAt: nil)
        #expect(throws: Never.self) { try payload.validate() }

        let stranger = TerminalTheme.default.reidentified(id: UUID())
        payload.themeRecords[0] = ICloudTerminalThemeRecord(
            theme: makeICloudTheme(stranger), origin: .builtIn, modifiedAt: now, deletedAt: nil)
        #expect(throws: ICloudSettingsSyncError.self) { try payload.validate() }

        var library = TerminalThemeLibrary.initial(at: .distantPast)
        library.merge(TerminalThemeLibrary(
            records: [TerminalThemeRecord(theme: legacy, origin: .builtIn, modifiedAt: now, deletedAt: nil)],
            selectedThemeID: TerminalTheme.legacyDefaultID, selectionModifiedAt: now))
        #expect(library.records.filter(\.isBuiltIn).map(\.id) == [TerminalTheme.defaultID])
        #expect(library.selectedThemeID == TerminalTheme.defaultID)
    }

    @Test func newerThemeLibrarySchemaIsPreservedReadOnly() throws {
        let suiteName = "sh.glas.test.theme-library-future.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var futureLibrary = TerminalThemeLibrary.initial()
        futureLibrary.schemaVersion = TerminalThemeLibrary.currentSchemaVersion + 1
        let originalData = try JSONEncoder().encode(futureLibrary)
        defaults.set(originalData, forKey: UserDefaultsKeys.themeLibrary)
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)

        settings.loadTheme()
        settings.saveTheme(TerminalTheme.default.reidentified(name: "Must Not Persist"))

        #expect(settings.themeLibraryLoadError != nil)
        #expect(defaults.data(forKey: UserDefaultsKeys.themeLibrary) == originalData)
    }

    @Test func themeLibraryCRUDProtectsBuiltInAndRetainsDeletionTombstone() throws {
        let suiteName = "sh.glas.test.theme-library-crud.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        settings.loadTheme()
        let builtInID = settings.selectedThemeID

        #expect(!settings.deleteTheme(id: builtInID))
        let duplicateID = try #require(settings.duplicateTheme(id: builtInID))
        #expect(settings.themeLibrary.activeRecords.count == 2)
        #expect(settings.selectedThemeID == duplicateID)

        #expect(settings.deleteTheme(id: duplicateID))
        #expect(settings.selectedThemeID == builtInID)
        #expect(settings.themeLibrary.activeRecords.count == 1)
        #expect(settings.themeLibrary.records.first(where: { $0.id == duplicateID })?.deletedAt != nil)
    }

    @Test func themeLibraryMergeUsesNewestRecordAndPropagatesDeletion() {
        let builtInID = UUID()
        let customID = UUID()
        let early = Date(timeIntervalSinceReferenceDate: 100)
        let late = Date(timeIntervalSinceReferenceDate: 200)
        let builtIn = TerminalTheme.default.reidentified(id: builtInID)
        let custom = TerminalTheme.default.reidentified(id: customID, name: "Custom")
        var local = TerminalThemeLibrary(
            records: [
                TerminalThemeRecord(theme: builtIn, origin: .builtIn, modifiedAt: early, deletedAt: nil),
                TerminalThemeRecord(theme: custom, origin: .custom, modifiedAt: early, deletedAt: nil),
            ],
            selectedThemeID: customID,
            selectionModifiedAt: early
        )
        let remote = TerminalThemeLibrary(
            records: [
                TerminalThemeRecord(theme: builtIn, origin: .builtIn, modifiedAt: early, deletedAt: nil),
                TerminalThemeRecord(theme: custom, origin: .custom, modifiedAt: late, deletedAt: late),
            ],
            selectedThemeID: builtInID,
            selectionModifiedAt: late
        )

        local.merge(remote)

        #expect(local.selectedThemeID == TerminalTheme.defaultID)
        #expect(local.activeRecords.map(\.id) == [TerminalTheme.defaultID])
        #expect(local.records.first(where: { $0.id == customID })?.deletedAt == late)
    }

    @Test func themeLibraryMergeBreaksEqualTimestampThemeConflictsDeterministically() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 300)
        let customID = UUID()
        var lightTheme = TerminalTheme.default.reidentified(id: customID, name: "Shared")
        lightTheme.background = CodableColor(sRGBRed: 0.8, green: 0.7, blue: 0.6)
        lightTheme.preferredAppearance = .light
        var darkTheme = lightTheme
        darkTheme.background = CodableColor(sRGBRed: 0.1, green: 0.2, blue: 0.3)
        darkTheme.preferredAppearance = .dark

        var first = TerminalThemeLibrary(
            records: [
                TerminalThemeRecord(
                    theme: TerminalTheme.default,
                    origin: .builtIn,
                    modifiedAt: timestamp,
                    deletedAt: nil
                ),
                TerminalThemeRecord(
                    theme: lightTheme,
                    origin: .custom,
                    modifiedAt: timestamp,
                    deletedAt: nil
                ),
            ],
            selectedThemeID: customID,
            selectionModifiedAt: timestamp
        )
        var second = TerminalThemeLibrary(
            records: [
                TerminalThemeRecord(
                    theme: TerminalTheme.default,
                    origin: .builtIn,
                    modifiedAt: timestamp,
                    deletedAt: nil
                ),
                TerminalThemeRecord(
                    theme: darkTheme,
                    origin: .custom,
                    modifiedAt: timestamp,
                    deletedAt: nil
                ),
            ],
            selectedThemeID: customID,
            selectionModifiedAt: timestamp
        )

        first.merge(second)
        second.merge(first)

        #expect(first == second)
        #expect(first.selectedTheme?.preferredAppearance != nil)
    }

    @Test @MainActor func iCloudSyncPreservesRemoteDeletionWhenStaleDevicePushes() async throws {
        let store = FakeICloudSettingsStore()
        let customID = UUID()
        let early = Date(timeIntervalSinceReferenceDate: 100)
        let late = Date(timeIntervalSinceReferenceDate: 200)
        let activePayload = makeICloudPayload(
            customID: customID,
            customDeletedAt: nil,
            modifiedAt: early
        )
        let deletedPayload = makeICloudPayload(
            customID: customID,
            customDeletedAt: late,
            modifiedAt: late
        )

        let firstDevice = ICloudSettingsSyncService(store: store, writerID: UUID())
        await firstDevice.start(onMerge: { _ in })
        _ = try await firstDevice.push(activePayload, writtenAt: early)
        _ = try await firstDevice.push(deletedPayload, writtenAt: late)

        let staleDevice = ICloudSettingsSyncService(store: store, writerID: UUID())
        await staleDevice.start(onMerge: { _ in })
        let converged = try await staleDevice.push(
            activePayload,
            writtenAt: late.addingTimeInterval(1)
        )

        #expect(converged.payload.themeRecords.first(where: { $0.id == customID })?.deletedAt == late)
        #expect(converged.payload.selectedThemeID == TerminalTheme.defaultID)
    }

    @Test @MainActor func iCloudPayloadRoundTripRetainsThemeMetadata() throws {
        let deletion = Date(timeIntervalSinceReferenceDate: 500)
        let basePayload = makeICloudPayload(
            customID: UUID(),
            customDeletedAt: deletion,
            modifiedAt: deletion
        )
        let appearances = TerminalThemeAppearance.allCases
        let appearanceThemes = appearances.map { appearance in
            var theme = TerminalTheme.default.reidentified(name: appearance.displayName)
            theme.preferredAppearance = appearance
            return theme
        }
        let payload = ICloudSettingsSyncPayload(
            themeRecords: [basePayload.themeRecords[0]] + appearanceThemes.map { theme in
                ICloudTerminalThemeRecord(
                    theme: makeICloudTheme(theme),
                    origin: .appleTerminal,
                    modifiedAt: deletion,
                    deletedAt: theme.preferredAppearance == .dark ? deletion : nil
                )
            },
            selectedThemeID: appearanceThemes[0].id,
            selectionModifiedAt: deletion,
            preferences: basePayload.preferences
        )

        let decoded = try JSONDecoder().decode(
            ICloudSettingsSyncPayload.self,
            from: JSONEncoder().encode(payload)
        )

        #expect(decoded == payload)
        for theme in appearanceThemes {
            let record = decoded.themeRecords.first(where: { $0.id == theme.id })
            #expect(record?.origin == .appleTerminal)
            #expect(record?.theme.preferredAppearance == theme.preferredAppearance)
        }
        let darkID = try #require(
            appearanceThemes.first(where: { $0.preferredAppearance == .dark })?.id
        )
        #expect(decoded.themeRecords.first(where: { $0.id == darkID })?.deletedAt == deletion)
    }

    @Test @MainActor func macImportedThemeAndPortableAppearanceApplyAfterICloudMerge() async throws {
        let sourceSuite = "sh.glas.test.icloud-source.\(UUID().uuidString)"
        let destinationSuite = "sh.glas.test.icloud-destination.\(UUID().uuidString)"
        let sourceDefaults = try #require(UserDefaults.forTest(suiteName: sourceSuite))
        let destinationDefaults = try #require(UserDefaults.forTest(suiteName: destinationSuite))
        defer {
            sourceDefaults.removePersistentDomain(forName: sourceSuite)
            destinationDefaults.removePersistentDomain(forName: destinationSuite)
        }
        sourceDefaults.set(true, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)
        destinationDefaults.set(true, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)

        let store = FakeICloudSettingsStore()
        let sourceService = ICloudSettingsSyncService(store: store, writerID: UUID())
        let source = SettingsManager(
            settingsDefaults: sourceDefaults,
            iCloudSettingsSyncService: sourceService
        )

        var imported = TerminalTheme.default.reidentified(name: "Mac Imported")
        imported.background = CodableColor(sRGBRed: 0.11, green: 0.12, blue: 0.13, alpha: 0.2)
        imported.foreground = CodableColor(sRGBRed: 0.91, green: 0.82, blue: 0.73)
        imported.cursor = CodableColor(sRGBRed: 0.81, green: 0.72, blue: 0.63)
        imported.selection = CodableColor(sRGBRed: 0.21, green: 0.32, blue: 0.43, alpha: 0.54)
        let ansiKeyPaths: [WritableKeyPath<TerminalTheme, CodableColor>] = [
            \.black, \.red, \.green, \.yellow, \.blue, \.magenta, \.cyan, \.white,
            \.brightBlack, \.brightRed, \.brightGreen, \.brightYellow,
            \.brightBlue, \.brightMagenta, \.brightCyan, \.brightWhite,
        ]
        for (index, keyPath) in ansiKeyPaths.enumerated() {
            let value = Double(index + 1) / 20
            imported[keyPath: keyPath] = CodableColor(
                sRGBRed: value,
                green: 1 - value,
                blue: Double((index * 3) % 17) / 20
            )
        }
        imported.fontName = "Menlo-Regular"
        imported.fontSize = 17
        imported.preferredAppearance = .dark
        let importedID = try #require(source.addImportedTheme(imported))
        let expectedTheme = imported.reidentified(id: importedID)

        source.windowOpacity = 0.27
        source.blurBackground = 0.63
        source.initialTerminalColumns = 172
        source.initialTerminalRows = 55
        source.glassTint = "#AF52DE"
        source.glassFrost = "regular"
        source.interactiveGlass = false
        source.cursorStyle = "Bar"
        source.blinkingCursor = false
        source.saveSettings()

        // 30 s, not 5: the push runs on the main actor, which the full suite's editor-layout tests
        // hold for seconds at a time; both waits expired there (2026-09-29). Polling stops the
        // moment the sync lands, so a passing run is no slower.
        let syncDeadline = ContinuousClock.now + .seconds(30)
        while sourceService.acceptedEnvelope?.payload.selectedThemeID != importedID,
              ContinuousClock.now < syncDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(sourceService.acceptedEnvelope?.payload.selectedThemeID == importedID)

        let destinationService = ICloudSettingsSyncService(store: store, writerID: UUID())
        let destination = SettingsManager(
            settingsDefaults: destinationDefaults,
            iCloudSettingsSyncService: destinationService
        )

        let destinationSyncDeadline = ContinuousClock.now + .seconds(30)
        while destination.selectedThemeID != importedID,
              ContinuousClock.now < destinationSyncDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(destination.selectedThemeID == importedID)
        #expect(destination.themeLibrary.activeRecords.first(where: { $0.id == importedID })?.origin == .appleTerminal)
        #expect(destination.currentTheme == expectedTheme)
        #expect(destination.currentTheme.ansiColors == expectedTheme.ansiColors)
        #expect(destination.currentTheme.swiftTermTheme == expectedTheme.swiftTermTheme)
        // The three appearance values are the shell's layer state: still carried in the payload
        // for glas.sh's readers, but a device's own Appearance choice is never overwritten by a
        // synced payload (that rewrote the toggle on every relaunch).
        let accepted = try #require(sourceService.acceptedEnvelope?.payload.preferences)
        #expect(accepted.windowOpacity == 0.27)
        #expect(accepted.blurBackground == 0.63)
        #expect(accepted.glassFrost == "regular")
        #expect(destination.windowOpacity == GlassLayerState.default.effectiveOpacity)
        #expect(destination.blurBackground == GlassLayerState.default.frost)
        #expect(destination.glassFrost == GlassLayerState.default.material.rawValue)
        #expect(destination.initialTerminalColumns == 172)
        #expect(destination.initialTerminalRows == 55)
        #expect(destination.glassTint == "#AF52DE")
        #expect(destination.interactiveGlass == false)
        #expect(destination.cursorStyle == "Bar")
        #expect(destination.blinkingCursor == false)
    }

    @Test func newTerminalFooterUsesThePlatformNativeRoute() {
        var openedConnections = false
        var openedMacTab = false
        let route = TerminalNewTerminalRoute.platformDefault

        route.perform(
            openConnections: { openedConnections = true },
            openMacTab: { openedMacTab = true }
        )

        #if os(macOS)
        #expect(route == .macTab)
        #expect(route.accessibilityLabel == "New Terminal Tab")
        #expect(!openedConnections)
        #expect(openedMacTab)
        #else
        #expect(route == .connections)
        #expect(route.accessibilityLabel == "New Terminal")
        #expect(openedConnections)
        #expect(!openedMacTab)
        #endif
    }

    #if os(visionOS) || os(iOS)
    @Test @MainActor func platformNewTerminalCommandInvokesTheFocusedRoute() {
        var invocationCount = 0
        let action = PlatformNewTerminalAction(title: "New Terminal Tab") {
            invocationCount += 1
        }

        #expect(action.title == "New Terminal Tab")
        action()
        #expect(invocationCount == 1)
    }
    #endif

    @Test func terminalSettingsExposeEveryHistoricalSection() {
        #expect(TerminalSettingsModalTab.allCases == [
            .overrides,
            .terminal,
            .portForwarding,
        ])
        #expect(TerminalSettingsModalTab.allCases.map(\.title) == [
            "This Window",
            "All Terminals",
            "Port Forwarding",
        ], "named for what they change, the window's own first")
        #expect(TerminalSettingsSheet.firstTab(hasWindowSettings: true) == .overrides,
                "opened from a terminal in a window, Settings starts on that window")
        #expect(TerminalSettingsSheet.firstTab(hasWindowSettings: false) == .terminal)
    }

    @Test @MainActor func disabledICloudSyncDoesNotObserveOrWrite() {
        let suiteName = "sh.glas.test.icloud-disabled.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)
        let store = FakeICloudSettingsStore()
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())

        _ = SettingsManager(
            settingsDefaults: defaults,
            iCloudSettingsSyncService: service
        )

        #expect(store.observerCount == 0)
        #expect(store.setCount == 0)
    }

    @Test @MainActor func stoppedICloudStartIgnoresStaleSynchronizationFailure() async throws {
        let store = FakeICloudSettingsStore()
        store.suspendsSynchronization = true
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        let startTask = Task { @MainActor in
            await service.start(onMerge: { _ in })
        }

        guard try await waitForPendingSynchronizations(1, in: store) else {
            Issue.record("The initial iCloud synchronization did not suspend")
            return
        }
        service.stop()
        store.resumeNextSynchronization(returning: false)
        await startTask.value

        #expect(service.status == .disabled)
        #expect(service.lastErrorDescription == nil)
        #expect(store.observerCount == 0)
    }

    @Test @MainActor func stoppedICloudAccountRefreshIgnoresStaleCompletion() async throws {
        let store = FakeICloudSettingsStore()
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        await service.start(onMerge: { _ in })
        #expect(service.status == .synced)

        store.suspendsSynchronization = true
        store.emit(ICloudSettingsStoreChange(reason: .account, changedKeys: []))
        guard try await waitForPendingSynchronizations(1, in: store) else {
            Issue.record("The account-change synchronization did not suspend")
            return
        }
        service.stop()
        store.resumeNextSynchronization(returning: true)
        try await Task.sleep(for: .milliseconds(10))

        #expect(service.status == .disabled)
        #expect(service.acceptedEnvelope == nil)
        #expect(store.observerCount == 0)
    }

    @Test @MainActor func supersededICloudAccountFailureCannotOverrideLatestRefresh() async throws {
        let store = FakeICloudSettingsStore()
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        await service.start(onMerge: { _ in })

        store.suspendsSynchronization = true
        store.emit(ICloudSettingsStoreChange(reason: .account, changedKeys: []))
        guard try await waitForPendingSynchronizations(1, in: store) else {
            Issue.record("The first account-change synchronization did not suspend")
            return
        }
        store.emit(ICloudSettingsStoreChange(reason: .account, changedKeys: []))
        guard try await waitForPendingSynchronizations(2, in: store) else {
            Issue.record("The replacement account-change synchronization did not suspend")
            return
        }

        store.resumeNextSynchronization(returning: false)
        try await Task.sleep(for: .milliseconds(10))
        #expect(service.status == .syncing)

        store.resumeNextSynchronization(returning: true)
        for _ in 0..<40 {
            if service.status == .synced { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(service.status == .synced)
        #expect(service.lastErrorDescription == nil)
    }

    @Test @MainActor func stoppedICloudPushCannotPublishStaleCompletion() async throws {
        let store = FakeICloudSettingsStore()
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        await service.start(onMerge: { _ in })
        store.suspendsSynchronization = true
        let payload = makeICloudPayload(
            customID: UUID(),
            customDeletedAt: nil,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let pushTask = Task { @MainActor in
            try await service.push(payload)
        }

        guard try await waitForPendingSynchronizations(1, in: store) else {
            Issue.record("The outgoing iCloud synchronization did not suspend")
            return
        }
        service.stop()
        store.resumeNextSynchronization(returning: true)

        do {
            _ = try await pushTask.value
            Issue.record("A push completed after iCloud synchronization stopped")
        } catch is CancellationError {
            // Expected: a stopped generation cannot publish its completion.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }

        #expect(service.status == .disabled)
        #expect(service.acceptedEnvelope == nil)
        #expect(service.lastErrorDescription == nil)
    }

    @Test @MainActor func settingsManagerTreatsStoppedICloudPushAsExpectedCancellation() async throws {
        let suiteName = "sh.glas.test.icloud-push-cancellation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)
        let store = FakeICloudSettingsStore()
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        let settings = SettingsManager(
            settingsDefaults: defaults,
            iCloudSettingsSyncService: service
        )

        for _ in 0..<100 {
            if store.setCount == 1, settings.iCloudSyncStatusText == "Up to date" { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.setCount == 1)
        #expect(settings.iCloudSyncStatusText == "Up to date")

        store.suspendsSynchronization = true
        settings.windowOpacity = 0.42
        settings.saveSettings()
        guard try await waitForPendingSynchronizations(1, in: store) else {
            Issue.record("The SettingsManager iCloud push did not suspend")
            return
        }
        let writeCountAtCancellation = store.setCount
        settings.setICloudSyncEnabled(false)
        store.resumeNextSynchronization(returning: true)
        try await Task.sleep(for: .milliseconds(100))

        #expect(settings.iCloudSyncStatusText == "Off")
        #expect(service.status == .disabled)
        #expect(store.observerCount == 0)
        #expect(store.setCount == writeCountAtCancellation)
    }

    @Test @MainActor func iCloudSyncRetriesTransientStoreFailure() async throws {
        let suiteName = "sh.glas.test.icloud-retry.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)
        let store = FakeICloudSettingsStore()
        store.synchronizeResult = false
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        let settings = SettingsManager(
            settingsDefaults: defaults,
            iCloudSettingsSyncService: service
        )

        try await Task.sleep(for: .milliseconds(650))
        #expect(settings.iCloudSyncStatusText.contains("unavailable"))
        let failedAttemptCount = store.setCount
        store.synchronizeResult = true

        for _ in 0..<100 {
            if store.setCount > failedAttemptCount,
               settings.iCloudSyncStatusText == "Up to date" {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.setCount > failedAttemptCount)
        #expect(settings.iCloudSyncStatusText == "Up to date")
    }

    @Test @MainActor func iCloudSyncWaitsForAccountChangeWithoutPolling() async throws {
        let suiteName = "sh.glas.test.icloud-account.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)
        let store = FakeICloudSettingsStore()
        store.isAccountAvailable = false
        let service = ICloudSettingsSyncService(store: store, writerID: UUID())
        let settings = SettingsManager(
            settingsDefaults: defaults,
            iCloudSettingsSyncService: service
        )

        try await Task.sleep(for: .milliseconds(650))
        #expect(store.observerCount == 1)
        #expect(store.setCount == 0)
        #expect(settings.iCloudSyncStatusText.contains("iCloud account"))

        // Account absence is persistent state, not a transport failure. Waiting
        // beyond the former first retry proves no polling push is scheduled.
        try await Task.sleep(for: .milliseconds(2_200))
        #expect(store.setCount == 0)

        store.isAccountAvailable = true
        store.emit(ICloudSettingsStoreChange(reason: .account, changedKeys: []))
        for _ in 0..<40 {
            if store.setCount == 1 && settings.iCloudSyncStatusText == "Up to date" {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(store.setCount == 1)
        #expect(settings.iCloudSyncStatusText == "Up to date")
    }

    @Test @MainActor func terminalEmulatorAppliesCarriageReturnInPlace() {
        let terminal = TerminalEmulator(cols: 40, rows: 4)

        terminal.feed(text: "Progress 10%\rProgress 20%")

        #expect(String(terminal.rows[0].prefix(12)) == "Progress 20%")
        #expect(!terminal.rows[0].contains("Progress 10%"))
    }

    @Test @MainActor func terminalEmulatorRestoresNormalBufferAfterAlternateScreen() {
        let terminal = TerminalEmulator(cols: 20, rows: 4)
        terminal.feed(text: "normal")

        terminal.feed(text: "\u{1B}[?1049h")
        #expect(terminal.isAlternateBufferActive)
        terminal.feed(text: "alternate")
        #expect(terminal.rows.joined().contains("alternate"))

        terminal.feed(text: "\u{1B}[?1049l")
        #expect(!terminal.isAlternateBufferActive)
        #expect(terminal.rows.joined().contains("normal"))
        #expect(!terminal.rows.joined().contains("alternate"))
    }

    @Test @MainActor func terminalEmulatorTracksGeometryAcrossResize() {
        let terminal = TerminalEmulator(cols: 10, rows: 4)
        terminal.feed(text: "abcdefghijklmno")

        terminal.resize(cols: 5, rows: 4)

        #expect(terminal.columns == 5)
        #expect(terminal.rowCount == 4)
        #expect(terminal.cursor.col < terminal.columns)

        terminal.resize(cols: 5, rows: 5)
        #expect(terminal.rowCount == 5)
    }

    @Test @MainActor func terminalEmulatorHandlesFragmentedAndMalformedUTF8() {
        let expected = "A€終B"
        let bytes = Data(expected.utf8)
        for split in 1..<bytes.count {
            let terminal = TerminalEmulator(cols: 20, rows: 2)
            terminal.feed(data: bytes.prefix(split))
            terminal.feed(data: bytes.suffix(from: split))
            let renderedScalars = terminal.styledRows[0]
                .filter { $0.columnWidth > 0 }
                .map(\.scalar)
                .joined()
            #expect(renderedScalars.hasPrefix(expected), "UTF-8 split failed at byte \(split)")
        }

        let malformed = TerminalEmulator(cols: 20, rows: 2)
        malformed.feed(data: Data([0x41, 0xF0, 0x28, 0x8C, 0x28, 0x42]))
        let rendered = malformed.rows.joined()
        #expect(rendered.contains("A"))
        #expect(rendered.contains("B"))
        malformed.feed(text: "C")
        #expect(malformed.rows.joined().contains("C"))
    }

    @Test @MainActor func terminalEmulatorPreservesGraphemesWidthsAndLogicalRTLOrder() {
        let terminal = TerminalEmulator(cols: 20, rows: 2)
        terminal.feed(text: "e\u{301}界ما")

        let cells = terminal.styledRows[0]
        #expect(cells[0].scalar == "e\u{301}")
        #expect(cells[0].columnWidth == 1)
        #expect(cells[1].scalar == "界")
        #expect(cells[1].columnWidth == 2)
        #expect(cells[2].columnWidth == 0)
        #expect(terminal.rows[0].contains("ما"), "SwiftTerm 1.13 preserves RTL input in logical order")
    }

    @Test @MainActor func terminalEmulatorExposesSGRStylesAndColors() {
        let terminal = TerminalEmulator(cols: 10, rows: 2)
        terminal.feed(text: "\u{1B}[1;3;4;38;2;1;2;3;48;2;4;5;6mX\u{1B}[0;7mY")

        let styled = terminal.styledRows[0]
        #expect(styled[0].scalar == "X")
        #expect(styled[0].style.foreground == TerminalRGBColor(red: 1, green: 2, blue: 3))
        #expect(styled[0].style.background == TerminalRGBColor(red: 4, green: 5, blue: 6))
        #expect(styled[0].style.isBold)
        #expect(styled[0].style.isItalic)
        #expect(styled[0].style.isUnderlined)
        #expect(styled[1].scalar == "Y")
        #expect(styled[1].style.isInverse)
    }

    @Test @MainActor func terminalEmulatorExposesProtocolModesAndOutboundReplies() {
        let terminal = TerminalEmulator(cols: 20, rows: 4)

        terminal.feed(text: "\u{1B}[?2004h")
        #expect(terminal.isBracketedPasteModeActive)
        terminal.feed(text: "\u{1B}[?1000h")
        #expect(terminal.mouseReportingMode == .vt200)
        terminal.feed(text: "\u{1B}[>1u")
        #expect(terminal.kittyKeyboardFlagsRawValue == 1)
        terminal.feed(text: "\u{1B}[?2026h")
        #expect(terminal.isSynchronizedOutputActive)
        terminal.feed(text: "synchronized")
        terminal.feed(text: "\u{1B}[?2026l")
        #expect(!terminal.isSynchronizedOutputActive)
        terminal.feed(text: "\u{1B}[6n")
        #expect(!terminal.drainOutboundData().isEmpty)
        #expect(!terminal.outboundDataWasTruncated)
    }

    @Test @MainActor func terminalEmulatorReportsBoundedScrollbackState() {
        let terminal = TerminalEmulator(cols: 20, rows: 3)
        for index in 0..<24 {
            terminal.feed(text: "line-\(index)\r\n")
        }

        #expect(terminal.bufferLineCount > terminal.rowCount)
        #expect(terminal.scrollbackLineCount == terminal.bufferLineCount - terminal.rowCount)
        #expect(terminal.rows.joined().contains("line-23"))
    }

    @Test func sshConfigParserParsesSafeDirectives() async throws {
        let input = """
        Host devbox
          HostName dev.internal
          User casey
          Port 2222
          IdentityFile ~/.ssh/id_ed25519
        """

        let (entries, warnings) = SSHConfigParser.parse(input)

        #expect(entries.count == 1)
        #expect(entries.first?.alias == "devbox")
        #expect(entries.first?.hostName == "dev.internal")
        #expect(entries.first?.user == "casey")
        #expect(entries.first?.port == 2222)
        #expect(entries.first?.identityFile == "~/.ssh/id_ed25519")
        #expect(warnings.isEmpty)
    }

    @Test func sshConfigParserBlocksUnsafeDirectives() async throws {
        let input = """
        Host prod
          HostName prod.example.com
          User root
          ProxyCommand nc %h %p
          LocalCommand echo hacked
        """

        let (entries, warnings) = SSHConfigParser.parse(input)

        #expect(entries.count == 1)
        #expect(entries.first?.alias == "prod")
        #expect(warnings.count >= 2)
    }


    // MARK: - Constants Tests

    @Test func userDefaultsKeysAreConsistent() {
        // Verify keys don't have typos by checking they round-trip through UserDefaults
        let testSuite = UserDefaults.forTest(suiteName: "sh.glas.test.constants")!
        defer { testSuite.removePersistentDomain(forName: "sh.glas.test.constants") }

        testSuite.set(true, forKey: UserDefaultsKeys.autoReconnect)
        #expect(testSuite.bool(forKey: UserDefaultsKeys.autoReconnect) == true)

        testSuite.set(42, forKey: UserDefaultsKeys.maxScrollbackLines)
        #expect(testSuite.integer(forKey: UserDefaultsKeys.maxScrollbackLines) == 42)

        testSuite.set("Block", forKey: UserDefaultsKeys.cursorStyle)
        #expect(testSuite.string(forKey: UserDefaultsKeys.cursorStyle) == "Block")
    }

    @Test func keychainConfigServiceNamesAreWellFormed() {
        let config = KeychainManager.config
        #expect(config.passwordsService.hasPrefix("sh.glas."))
        #expect(config.sshKeysPrivateService.hasPrefix("sh.glas."))
        #expect(config.sshKeysPassphraseService.hasPrefix("sh.glas."))
        #expect(config.sealedP256Service.hasPrefix("sh.glas."))
        #expect(config.sealedP256TagService.hasPrefix("sh.glas."))
    }

    @Test func keychainAccountsAreTerminalNamespacedAndProfileStable() {
        let serverID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        #expect(
            KeychainManager.serverPasswordAccount(for: serverID)
                == "terminal.server-password.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
        #expect(KeychainManager.tailscaleAPIKeyAccount == "terminal.tailscale.api-key")
        #expect(KeychainManager.tailscaleOAuthClientIDAccount == "terminal.tailscale.oauth.client-id")
        #expect(KeychainManager.tailscaleOAuthClientSecretAccount == "terminal.tailscale.oauth.client-secret")
        #expect(KeychainManager.tailscaleOAuthCredentialsAccount == "terminal.tailscale.oauth.credentials")
    }

    @Test func sharedSSHCredentialContractMatchesGlassDB() throws {
        let server = migrationServer(host: "bastion.example.com")
        #expect(KeychainManager.sharedSSHPasswordAccount(for: server)
            == "ssh:operator@bastion.example.com:22")
        #expect(KeychainManager.config.sshPasswordsService == "sh.glas.sshpasswords")
        #expect(KeychainManager.validatedSharedAccessGroup("7JQGQ7CRH8.sh.glas.shared")
            == "7JQGQ7CRH8.sh.glas.shared")
        #expect(KeychainManager.validatedSharedAccessGroup("sh.glas.shared") == nil)
        #expect(KeychainManager.validatedSharedAccessGroup("$(AppIdentifierPrefix)sh.glas.shared") == nil)
    }

    @Test func glasPasswordSavePublishesVerifiedGlassDBCompatibleCredential() throws {
        let server = migrationServer(host: "bastion.example.com")
        let probe = SharedServerCredentialProbe()
        try KeychainManager.savePassword("shared-secret", for: server, store: probe.store)

        let primaryKey = probe.key(
            account: KeychainManager.serverPasswordAccount(for: server.id),
            service: KeychainManager.config.passwordsService
        )
        let sharedKey = probe.key(
            account: try #require(KeychainManager.sharedSSHPasswordAccount(for: server)),
            service: KeychainManager.config.sshPasswordsService
        )
        #expect(probe.values[primaryKey] == Data("shared-secret".utf8))
        #expect(probe.values[sharedKey] == Data("shared-secret".utf8))
    }

    @Test func glassDBCompatibleCredentialImportsForwardIntoGlasProfile() throws {
        let server = migrationServer(host: "bastion.example.com")
        let probe = SharedServerCredentialProbe()
        let sharedAccount = try #require(KeychainManager.sharedSSHPasswordAccount(for: server))
        let sharedKey = probe.key(
            account: sharedAccount,
            service: KeychainManager.config.sshPasswordsService
        )
        probe.values[sharedKey] = Data("glassdb-secret".utf8)

        #expect(try KeychainManager.retrievePassword(for: server, store: probe.store) == "glassdb-secret")
        let primaryKey = probe.key(
            account: KeychainManager.serverPasswordAccount(for: server.id),
            service: KeychainManager.config.passwordsService
        )
        #expect(probe.values[primaryKey] == Data("glassdb-secret".utf8))

        try KeychainManager.deletePassword(for: server, store: probe.store)
        #expect(probe.values[primaryKey] == nil)
        #expect(probe.values[sharedKey] == Data("glassdb-secret".utf8))
    }

    @Test func sharedCompatibilityCleanupRetainsTheGlasProfileCredential() throws {
        let server = migrationServer(host: "bastion.example.com")
        let probe = SharedServerCredentialProbe()
        try KeychainManager.savePassword("shared-secret", for: server, store: probe.store)

        let primaryKey = probe.key(
            account: KeychainManager.serverPasswordAccount(for: server.id),
            service: KeychainManager.config.passwordsService
        )
        let sharedKey = probe.key(
            account: try #require(KeychainManager.sharedSSHPasswordAccount(for: server)),
            service: KeychainManager.config.sshPasswordsService
        )

        try KeychainManager.deleteSharedCompatibilityPassword(
            for: server,
            store: probe.store
        )

        #expect(probe.values[primaryKey] == Data("shared-secret".utf8))
        #expect(probe.values[sharedKey] == nil)
    }

    @Test func sharedCredentialPartialWriteRestoresBothPreviousRecords() throws {
        let server = migrationServer(host: "bastion.example.com")
        let probe = SharedServerCredentialProbe()
        let primaryKey = probe.key(
            account: KeychainManager.serverPasswordAccount(for: server.id),
            service: KeychainManager.config.passwordsService
        )
        let sharedKey = probe.key(
            account: try #require(KeychainManager.sharedSSHPasswordAccount(for: server)),
            service: KeychainManager.config.sshPasswordsService
        )
        probe.values[primaryKey] = Data("old-primary".utf8)
        probe.values[sharedKey] = Data("old-shared".utf8)
        probe.failSaveKey = sharedKey

        #expect(throws: TerminalWriteFailure.self) {
            try KeychainManager.savePassword("new-secret", for: server, store: probe.store)
        }
        #expect(probe.values[primaryKey] == Data("old-primary".utf8))
        #expect(probe.values[sharedKey] == Data("old-shared".utf8))
    }

    private func migrationServer(
        id: UUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        host: String = "terminal.example.com"
    ) -> ServerConfiguration {
        ServerConfiguration(id: id, name: "Terminal", host: host, username: "operator")
    }

    @Test func credentialMigrationCopiesOnlyExclusiveServerAndShippedTailscaleCredentials() throws {
        let server = migrationServer()
        let probe = CredentialMigrationProbe()
        let legacyServer = KeychainManager.legacyServerPasswordAccount(for: server)
        probe.values[legacyServer] = Data("terminal-password".utf8)
        probe.values[KeychainManager.legacyTailscaleAPIKeyAccount] = Data("ts-api".utf8)
        probe.values[KeychainManager.legacyTailscaleOAuthClientIDAccount] = Data("client-id".utf8)
        probe.values[KeychainManager.legacyTailscaleOAuthClientSecretAccount] = Data("client-secret".utf8)

        let first = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: probe.store
        )

        #expect(first.state == .completed)
        #expect(first.exclusiveServerTupleCount == 1)
        #expect(first.migratedServerDestinationCount == 1)
        #expect(first.tailscaleLegacySourceCount == 3)
        #expect(first.tailscaleMigratedCredentialCount == 2)
        #expect(probe.values[KeychainManager.serverPasswordAccount(for: server.id)] == Data("terminal-password".utf8))
        #expect(probe.values[KeychainManager.tailscaleAPIKeyAccount] == Data("ts-api".utf8))
        #expect(probe.values[legacyServer] == Data("terminal-password".utf8))
        #expect(probe.values[KeychainManager.legacyTailscaleAPIKeyAccount] == Data("ts-api".utf8))
        #expect(probe.version == KeychainManager.currentCredentialMigrationVersion)

        let writesAfterFirstRun = probe.writeCount
        let second = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: probe.store
        )
        #expect(second == first)
        #expect(probe.writeCount == writesAfterFirstRun)
    }

    @Test func credentialMigrationRetainsAmbiguousAndUnavailableMetadataServerTuples() throws {
        let server = migrationServer()
        let legacy = KeychainManager.legacyServerPasswordAccount(for: server)

        let ambiguous = CredentialMigrationProbe()
        ambiguous.values[legacy] = Data("shared".utf8)
        let ambiguousReport = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: [legacy]),
            store: ambiguous.store
        )
        #expect(ambiguousReport.ambiguousServerTupleCount == 1)
        #expect(ambiguous.values[legacy] == Data("shared".utf8))
        #expect(ambiguous.values[KeychainManager.serverPasswordAccount(for: server.id)] == nil)

        let unavailable = CredentialMigrationProbe()
        unavailable.values[legacy] = Data("unknown-owner".utf8)
        let unavailableReport = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .unavailable,
            store: unavailable.store
        )
        #expect(unavailableReport.unavailableMetadataTupleCount == 1)
        #expect(unavailable.values[legacy] == Data("unknown-owner".utf8))
        #expect(unavailable.values[KeychainManager.serverPasswordAccount(for: server.id)] == nil)
    }

    @Test func credentialMigrationDeduplicatesMatchingDestinationAndRetainsConflicts() throws {
        let server = migrationServer()
        let legacy = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)

        let matching = CredentialMigrationProbe()
        matching.values[legacy] = Data("same".utf8)
        matching.values[destination] = Data("same".utf8)
        let matchingReport = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: matching.store
        )
        #expect(matchingReport.alreadyPresentDestinationCount == 1)
        #expect(matchingReport.migratedServerDestinationCount == 0)
        #expect(matching.values[legacy] == Data("same".utf8))

        let conflicting = CredentialMigrationProbe()
        conflicting.values[legacy] = Data("legacy".utf8)
        conflicting.values[destination] = Data("canonical".utf8)
        let conflictReport = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: conflicting.store
        )
        #expect(conflictReport.conflictCount == 1)
        #expect(conflicting.values[legacy] == Data("legacy".utf8))
        #expect(conflicting.values[destination] == Data("canonical".utf8))
    }

    @Test func credentialMigrationCountsDuplicateProfilesDeterministically() throws {
        let first = migrationServer()
        let second = migrationServer(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )
        let legacy = KeychainManager.legacyServerPasswordAccount(for: first)
        let probe = CredentialMigrationProbe()
        probe.values[legacy] = Data("shared-terminal-password".utf8)

        let report = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [second, first],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: probe.store
        )

        #expect(report.serverProfileCount == 2)
        #expect(report.uniqueServerTupleCount == 1)
        #expect(report.duplicateServerProfileCount == 1)
        #expect(report.migratedServerDestinationCount == 2)
        #expect(probe.values[KeychainManager.serverPasswordAccount(for: first.id)] == Data("shared-terminal-password".utf8))
        #expect(probe.values[KeychainManager.serverPasswordAccount(for: second.id)] == Data("shared-terminal-password".utf8))
        #expect(probe.values[legacy] == Data("shared-terminal-password".utf8))
    }

    @Test func credentialMigrationQueryFailureDoesNotMutateOrAdvance() {
        let server = migrationServer()
        let probe = CredentialMigrationProbe()
        let legacy = KeychainManager.legacyServerPasswordAccount(for: server)
        probe.values[legacy] = Data("secret".utf8)
        probe.failReadAccounts.insert(legacy)

        #expect(throws: CredentialMigrationProbeError.self) {
            try KeychainManager.runCredentialMigrationIfNeeded(
                servers: [server],
                metadata: .available(glassDBLegacyPasswordAccounts: []),
                store: probe.store
            )
        }
        #expect(probe.values[legacy] == Data("secret".utf8))
        #expect(probe.values[KeychainManager.serverPasswordAccount(for: server.id)] == nil)
        #expect(probe.version == 0)
        #expect(probe.report?.state == .failed)
    }

    @Test func credentialMigrationReadbackFailurePreservesUnverifiableDestinationAndRemainsRetryable() throws {
        let server = migrationServer()
        let probe = CredentialMigrationProbe()
        let legacy = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)
        probe.values[legacy] = Data("secret".utf8)
        probe.omitReadbackAccounts.insert(destination)

        #expect(throws: CredentialMigrationError.self) {
            try KeychainManager.runCredentialMigrationIfNeeded(
                servers: [server],
                metadata: .available(glassDBLegacyPasswordAccounts: []),
                store: probe.store
            )
        }
        #expect(probe.values[legacy] == Data("secret".utf8))
        // A missing readback cannot distinguish an absent destination from a
        // concealed or concurrently replaced value. Rollback must not delete it.
        #expect(probe.values[destination] == Data("secret".utf8))
        #expect(probe.version == 0)
        #expect(probe.report?.failureCode == CredentialMigrationError.keychainReadbackMismatch.code)

        probe.omitReadbackAccounts.remove(destination)
        let retry = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: probe.store
        )
        #expect(retry.state == .completed)
        #expect(probe.values[destination] == Data("secret".utf8))
        #expect(probe.values[legacy] == Data("secret".utf8))
    }

    @Test func credentialMigrationReportFailureRollsBackBeforeSourceDeletion() {
        let server = migrationServer()
        let probe = CredentialMigrationProbe()
        let legacy = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)
        probe.values[legacy] = Data("secret".utf8)
        probe.failReportSave = true

        #expect(throws: CredentialMigrationProbeError.self) {
            try KeychainManager.runCredentialMigrationIfNeeded(
                servers: [server],
                metadata: .available(glassDBLegacyPasswordAccounts: []),
                store: probe.store
            )
        }
        #expect(probe.values[legacy] == Data("secret".utf8))
        #expect(probe.values[destination] == Data("secret".utf8))
        #expect(probe.version == 0)
    }

    @Test func credentialMigrationNeverQueriesOrDeletesForwardMigratedSources() throws {
        let probe = CredentialMigrationProbe()
        let clientIDAccount = KeychainManager.tailscaleOAuthClientIDAccount
        let clientSecretAccount = KeychainManager.tailscaleOAuthClientSecretAccount
        let destination = KeychainManager.tailscaleOAuthCredentialsAccount
        probe.values[clientIDAccount] = Data("client-id".utf8)
        probe.values[clientSecretAccount] = Data("client-secret".utf8)
        let report = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [],
            metadata: .unavailable,
            store: probe.store
        )
        #expect(probe.values[clientIDAccount] == Data("client-id".utf8))
        #expect(probe.values[clientSecretAccount] == Data("client-secret".utf8))
        #expect(probe.values[destination] != nil)
        #expect(report.deletedLegacySourceCount == 0)
        #expect(probe.deleteCount == 0)
        #expect(probe.version == KeychainManager.currentCredentialMigrationVersion)
    }

    @Test func credentialMigrationDoesNotInvokeDestructiveSourceAdapter() throws {
        let server = migrationServer()
        let source = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)
        let probe = CredentialMigrationProbe()
        probe.values[source] = Data("terminal-password".utf8)
        probe.failDeleteAfterMutationAccounts.insert(source)

        let report = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: probe.store
        )
        #expect(probe.values[source] == Data("terminal-password".utf8))
        #expect(probe.values[destination] == Data("terminal-password".utf8))
        #expect(report.deletedLegacySourceCount == 0)
        #expect(probe.deleteCount == 0)
    }

    @Test func credentialMigrationWriteFailureAfterMutationPreservesForwardDestinationAndRetries() throws {
        let server = migrationServer()
        let source = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)
        let probe = CredentialMigrationProbe()
        probe.values[source] = Data("terminal-password".utf8)
        probe.failWriteAfterMutationAccounts.insert(destination)

        #expect(throws: CredentialMigrationProbeError.self) {
            try KeychainManager.runCredentialMigrationIfNeeded(
                servers: [server],
                metadata: .available(glassDBLegacyPasswordAccounts: []),
                store: probe.store
            )
        }
        #expect(probe.values[source] == Data("terminal-password".utf8))
        #expect(probe.values[destination] == Data("terminal-password".utf8))
        #expect(probe.version == 0)

        probe.failWriteAfterMutationAccounts.remove(destination)
        let retry = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: probe.store
        )
        #expect(retry.state == .completed)
        #expect(probe.values[source] == Data("terminal-password".utf8))
        #expect(probe.values[destination] == Data("terminal-password".utf8))
    }

    @Test func credentialMigrationAtomicAddPreservesConcurrentDestination() throws {
        let server = migrationServer()
        let source = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)
        let replacement = Data("concurrent-owner-value".utf8)
        let probe = CredentialMigrationProbe()
        probe.values[source] = Data("terminal-password".utf8)
        probe.replaceAccountBeforeNextAdd = (destination, replacement)

        let report = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [server],
            metadata: .available(glassDBLegacyPasswordAccounts: []),
            store: probe.store
        )

        #expect(report.state == .completed)
        #expect(report.conflictCount == 1)
        #expect(report.migratedServerDestinationCount == 0)
        #expect(probe.values[source] == Data("terminal-password".utf8))
        #expect(probe.values[destination] == replacement)
    }

    @Test func credentialMigrationFailurePreservesConcurrentDestinationReplacement() {
        let server = migrationServer()
        let source = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)
        let replacement = Data("concurrent-owner-value".utf8)
        let probe = CredentialMigrationProbe()
        probe.values[source] = Data("terminal-password".utf8)
        probe.replaceAccountOnNextReportSave = (destination, replacement)

        do {
            try KeychainManager.runCredentialMigrationIfNeeded(
                servers: [server],
                metadata: .available(glassDBLegacyPasswordAccounts: []),
                store: probe.store
            )
            Issue.record("A concurrent destination replacement must surface the injected failure")
        } catch CredentialMigrationProbeError.persistenceFailure {
            // Expected.
        } catch {
            Issue.record("Expected persistenceFailure, received \(error)")
        }
        #expect(probe.values[source] == Data("terminal-password".utf8))
        #expect(probe.values[destination] == replacement)
        #expect(probe.version == 0)
    }

    @Test func credentialMigrationFailureRetainsOriginalSourceAndForwardDestination() {
        let server = migrationServer()
        let source = KeychainManager.legacyServerPasswordAccount(for: server)
        let destination = KeychainManager.serverPasswordAccount(for: server.id)
        let probe = CredentialMigrationProbe()
        probe.values[source] = Data("terminal-password".utf8)
        probe.replaceAccountOnNextCompletedReportSave = (
            destination,
            Data("terminal-password".utf8)
        )

        do {
            try KeychainManager.runCredentialMigrationIfNeeded(
                servers: [server],
                metadata: .available(glassDBLegacyPasswordAccounts: []),
                store: probe.store
            )
            Issue.record("The injected completed-report failure must be surfaced")
        } catch CredentialMigrationProbeError.persistenceFailure {
            // Expected; neither side is destructively rolled back.
        } catch {
            Issue.record("Expected persistenceFailure, received \(error)")
        }
        #expect(probe.values[source] == Data("terminal-password".utf8))
        #expect(probe.values[destination] == Data("terminal-password".utf8))
        #expect(probe.version == 0)
    }

    @Test func credentialMigrationBundlesTerminalScopedOAuthAndIsIdempotent() throws {
        let probe = CredentialMigrationProbe()
        let clientIDAccount = KeychainManager.tailscaleOAuthClientIDAccount
        let clientSecretAccount = KeychainManager.tailscaleOAuthClientSecretAccount
        let destination = KeychainManager.tailscaleOAuthCredentialsAccount
        probe.values[clientIDAccount] = Data("scoped-client-id".utf8)
        probe.values[clientSecretAccount] = Data("scoped-client-secret".utf8)

        let first = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [],
            metadata: .unavailable,
            store: probe.store
        )
        let bundle = try #require(probe.values[destination])
        let decoded = try #require(
            JSONSerialization.jsonObject(with: bundle) as? [String: String]
        )

        #expect(first.state == .completed)
        #expect(first.tailscaleLegacySourceCount == 2)
        #expect(first.tailscaleMigratedCredentialCount == 1)
        #expect(first.verifiedDestinationCount == 1)
        #expect(first.deletedLegacySourceCount == 0)
        #expect(decoded == [
            "clientID": "scoped-client-id",
            "clientSecret": "scoped-client-secret"
        ])
        let reportText = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
        #expect(!reportText.contains("scoped-client-id"))
        #expect(!reportText.contains("scoped-client-secret"))
        #expect(probe.values[clientIDAccount] == Data("scoped-client-id".utf8))
        #expect(probe.values[clientSecretAccount] == Data("scoped-client-secret".utf8))

        let writesAfterFirstRun = probe.writeCount
        let second = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [],
            metadata: .unavailable,
            store: probe.store
        )
        #expect(second == first)
        #expect(probe.writeCount == writesAfterFirstRun)
    }

    @Test func credentialMigrationPreservesOAuthSplitSourcesOnDestinationConflict() throws {
        let probe = CredentialMigrationProbe()
        let clientIDAccount = KeychainManager.tailscaleOAuthClientIDAccount
        let clientSecretAccount = KeychainManager.tailscaleOAuthClientSecretAccount
        let destination = KeychainManager.tailscaleOAuthCredentialsAccount
        let destinationData = try JSONSerialization.data(withJSONObject: [
            "clientID": "canonical-client-id",
            "clientSecret": "canonical-client-secret"
        ], options: [.sortedKeys])
        probe.values[clientIDAccount] = Data("split-client-id".utf8)
        probe.values[clientSecretAccount] = Data("split-client-secret".utf8)
        probe.values[destination] = destinationData

        let report = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [],
            metadata: .unavailable,
            store: probe.store
        )

        #expect(report.state == .completed)
        #expect(report.conflictCount == 1)
        #expect(report.deletedLegacySourceCount == 0)
        #expect(probe.values[clientIDAccount] == Data("split-client-id".utf8))
        #expect(probe.values[clientSecretAccount] == Data("split-client-secret".utf8))
        #expect(probe.values[destination] == destinationData)
    }

    @Test func credentialMigrationPreservesConflictingOAuthSourcePairs() throws {
        let probe = CredentialMigrationProbe()
        probe.values[KeychainManager.legacyTailscaleOAuthClientIDAccount] = Data("legacy-id".utf8)
        probe.values[KeychainManager.legacyTailscaleOAuthClientSecretAccount] = Data("legacy-secret".utf8)
        probe.values[KeychainManager.tailscaleOAuthClientIDAccount] = Data("scoped-id".utf8)
        probe.values[KeychainManager.tailscaleOAuthClientSecretAccount] = Data("scoped-secret".utf8)

        let report = try KeychainManager.runCredentialMigrationIfNeeded(
            servers: [],
            metadata: .unavailable,
            store: probe.store
        )

        #expect(report.state == .completed)
        #expect(report.conflictCount == 1)
        #expect(report.deletedLegacySourceCount == 0)
        #expect(probe.values[KeychainManager.legacyTailscaleOAuthClientIDAccount] == Data("legacy-id".utf8))
        #expect(probe.values[KeychainManager.legacyTailscaleOAuthClientSecretAccount] == Data("legacy-secret".utf8))
        #expect(probe.values[KeychainManager.tailscaleOAuthClientIDAccount] == Data("scoped-id".utf8))
        #expect(probe.values[KeychainManager.tailscaleOAuthClientSecretAccount] == Data("scoped-secret".utf8))
        #expect(probe.values[KeychainManager.tailscaleOAuthCredentialsAccount] == nil)
    }

    @Test func oauthReadSideMigrationVerifiesBundleAndRetainsSplitSources() throws {
        let probe = CredentialMigrationProbe()
        probe.values[KeychainManager.tailscaleOAuthClientIDAccount] = Data("client-id".utf8)
        probe.values[KeychainManager.tailscaleOAuthClientSecretAccount] = Data("client-secret".utf8)

        let credentials = try KeychainManager.retrieveTailscaleOAuthCredentials(store: probe.oauthStore)

        #expect(credentials.clientID == "client-id")
        #expect(credentials.clientSecret == "client-secret")
        #expect(probe.values[KeychainManager.tailscaleOAuthCredentialsAccount] != nil)
        #expect(probe.values[KeychainManager.tailscaleOAuthClientIDAccount] == Data("client-id".utf8))
        #expect(probe.values[KeychainManager.tailscaleOAuthClientSecretAccount] == Data("client-secret".utf8))
    }

    @Test func oauthReadSideMigrationDoesNotInvokeDestructiveSplitCleanup() throws {
        let probe = CredentialMigrationProbe()
        let clientIDAccount = KeychainManager.tailscaleOAuthClientIDAccount
        let clientSecretAccount = KeychainManager.tailscaleOAuthClientSecretAccount
        probe.values[clientIDAccount] = Data("client-id".utf8)
        probe.values[clientSecretAccount] = Data("client-secret".utf8)
        probe.failDeleteAfterMutationAccounts.insert(clientSecretAccount)

        let credentials = try KeychainManager.retrieveTailscaleOAuthCredentials(store: probe.oauthStore)
        #expect(credentials.clientID == "client-id")
        #expect(credentials.clientSecret == "client-secret")
        #expect(probe.values[KeychainManager.tailscaleOAuthCredentialsAccount] != nil)
        #expect(probe.values[clientIDAccount] == Data("client-id".utf8))
        #expect(probe.values[clientSecretAccount] == Data("client-secret".utf8))
        #expect(probe.deleteCount == 0)
    }

    @Test func oauthReadSideMigrationAtomicAddPreservesConcurrentBundle() throws {
        let probe = CredentialMigrationProbe()
        let destination = KeychainManager.tailscaleOAuthCredentialsAccount
        let replacement = try JSONSerialization.data(withJSONObject: [
            "clientID": "concurrent-id",
            "clientSecret": "concurrent-secret",
        ])
        probe.values[KeychainManager.tailscaleOAuthClientIDAccount] = Data("split-id".utf8)
        probe.values[KeychainManager.tailscaleOAuthClientSecretAccount] = Data("split-secret".utf8)
        probe.replaceAccountBeforeNextAdd = (destination, replacement)

        #expect(throws: CredentialMigrationError.self) {
            try KeychainManager.retrieveTailscaleOAuthCredentials(store: probe.oauthStore)
        }
        #expect(probe.values[destination] == replacement)
        #expect(probe.values[KeychainManager.tailscaleOAuthClientIDAccount] == Data("split-id".utf8))
        #expect(probe.values[KeychainManager.tailscaleOAuthClientSecretAccount] == Data("split-secret".utf8))
    }

    @Test func oauthDeleteAttemptsEveryAccountAndRetryRemovesPartialFailure() throws {
        let probe = CredentialMigrationProbe()
        let accounts = [
            KeychainManager.tailscaleOAuthCredentialsAccount,
            KeychainManager.tailscaleOAuthClientIDAccount,
            KeychainManager.tailscaleOAuthClientSecretAccount,
        ]
        for account in accounts {
            probe.values[account] = Data("credential".utf8)
        }
        probe.failDeleteAccounts.insert(KeychainManager.tailscaleOAuthClientIDAccount)

        #expect(throws: CredentialMigrationProbeError.self) {
            try KeychainManager.deleteTailscaleOAuthCredentials(store: probe.oauthStore)
        }
        #expect(probe.values[KeychainManager.tailscaleOAuthCredentialsAccount] == nil)
        #expect(probe.values[KeychainManager.tailscaleOAuthClientIDAccount] != nil)
        #expect(probe.values[KeychainManager.tailscaleOAuthClientSecretAccount] == nil)

        probe.failDeleteAccounts.remove(KeychainManager.tailscaleOAuthClientIDAccount)
        try KeychainManager.deleteTailscaleOAuthCredentials(store: probe.oauthStore)
        #expect(accounts.allSatisfy { probe.values[$0] == nil })
    }

    // MARK: - ServerManager Tests

    @Test func hostTrustMigrationWithoutSourcesSkipsKeychainInventory() async throws {
        let fixture = migrationDefaults("host-trust-empty")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let probe = HostTrustStoreProbe()
        let manager = ServerManager(
            loadImmediately: false,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )

        manager.loadServersIfNeeded()
        await manager.legacyHostTrustMigration?.value

        #expect(probe.allRecordsCount == 0)
        #expect(
            fixture.defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion)
                == ServerManager.currentHostTrustMigrationVersion
        )
        #expect(try migrationReport(from: fixture.defaults).state == .completed)
    }

    @Test func serverDeletionPersistsMetadataFirstAndRestoresItOnKeychainFailure() async throws {
        let suiteName = "sh.glas.test.server-delete.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let server = migrationServer()
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[server.id] = "original-secret"
        var observedPersistedRemoval = false
        let baseStore = passwordProbe.store
        let failingStore = ServerPasswordStore(
            retrieve: baseStore.retrieve,
            save: baseStore.save,
            delete: { _ in
                let data = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
                let persisted = try JSONDecoder().decode([ServerConfiguration].self, from: data)
                observedPersistedRemoval = persisted.isEmpty
                throw CredentialMigrationProbeError.queryFailure
            }
        )
        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            passwordStore: failingStore
        )
        manager.servers = [server]
        try await manager.persistServersOrThrow()

        await #expect(throws: CredentialMigrationProbeError.self) {
            try await manager.deleteServer(server)
        }
        #expect(observedPersistedRemoval)
        #expect(manager.servers == [server])
        #expect(passwordProbe.values[server.id] == "original-secret")
        #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) == nil)
        let restoredData = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: restoredData) == [server])
    }

    #if DEBUG
    @Test func uiTestFixturePurgeRemovesProfileAndSharedCredentialOnly() async throws {
        let suiteName = "sh.glas.test.ui-fixture-purge.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let probe = SharedServerCredentialProbe()
        let fixture = ServerConfiguration(
            name: "\(ServerManager.connectionLibraryUITestNamePrefix)ABC123",
            host: "192.0.2.1",
            port: 22,
            username: "ui-test",
            authMethod: .password
        )
        let retained = migrationServer(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            host: "retained.example.com"
        )
        let similarlyNamedRealServer = ServerConfiguration(
            id: UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-AAAAAAAAAAAA")!,
            name: "\(ServerManager.connectionLibraryUITestNamePrefix)Production",
            host: "similarly-named.example.com",
            username: "operator",
            authMethod: .password
        )
        let similarlyNamedKeyServer = ServerConfiguration(
            id: UUID(uuidString: "DDDDDDDD-EEEE-FFFF-AAAA-BBBBBBBBBBBB")!,
            name: "\(ServerManager.connectionLibraryUITestNamePrefix)Key",
            host: ServerManager.connectionLibraryUITestHost,
            username: ServerManager.connectionLibraryUITestUsername,
            authMethod: .sshKey
        )
        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            passwordStore: probe.passwordStore
        )
        manager.servers = [
            fixture,
            retained,
            similarlyNamedRealServer,
            similarlyNamedKeyServer,
        ]
        try await manager.persistServersOrThrow()
        try KeychainManager.savePassword(
            "fixture-secret",
            for: fixture,
            store: probe.store
        )
        try KeychainManager.savePassword(
            "retained-secret",
            for: retained,
            store: probe.store
        )
        try KeychainManager.savePassword(
            "similarly-named-secret",
            for: similarlyNamedRealServer,
            store: probe.store
        )

        try await manager.purgeConnectionLibraryUITestFixtures()
        try await manager.purgeConnectionLibraryUITestFixtures()

        let fixturePrimary = probe.key(
            account: KeychainManager.serverPasswordAccount(for: fixture.id),
            service: KeychainManager.config.passwordsService
        )
        let fixtureShared = probe.key(
            account: try #require(KeychainManager.sharedSSHPasswordAccount(for: fixture)),
            service: KeychainManager.config.sshPasswordsService
        )
        let retainedPrimary = probe.key(
            account: KeychainManager.serverPasswordAccount(for: retained.id),
            service: KeychainManager.config.passwordsService
        )
        let retainedShared = probe.key(
            account: try #require(KeychainManager.sharedSSHPasswordAccount(for: retained)),
            service: KeychainManager.config.sshPasswordsService
        )
        let similarlyNamedPrimary = probe.key(
            account: KeychainManager.serverPasswordAccount(
                for: similarlyNamedRealServer.id
            ),
            service: KeychainManager.config.passwordsService
        )
        let similarlyNamedShared = probe.key(
            account: try #require(
                KeychainManager.sharedSSHPasswordAccount(
                    for: similarlyNamedRealServer
                )
            ),
            service: KeychainManager.config.sshPasswordsService
        )
        #expect(manager.servers == [
            retained,
            similarlyNamedRealServer,
            similarlyNamedKeyServer,
        ])
        #expect(probe.values[fixturePrimary] == nil)
        #expect(probe.values[fixtureShared] == nil)
        #expect(probe.values[retainedPrimary] == Data("retained-secret".utf8))
        #expect(probe.values[retainedShared] == Data("retained-secret".utf8))
        #expect(probe.values[similarlyNamedPrimary] == Data("similarly-named-secret".utf8))
        #expect(probe.values[similarlyNamedShared] == Data("similarly-named-secret".utf8))
    }
    #endif

    @Test func serverPasswordCreateRestoresExactPriorUUIDSecretWhenMetadataReadbackFails() async throws {
        let suiteName = "sh.glas.test.server-create-rollback.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode([ServerConfiguration]()), forKey: UserDefaultsKeys.servers)

        let server = migrationServer()
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[server.id] = "preexisting-secret"
        var writeCount = 0
        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            passwordStore: passwordProbe.store,
            serverDataWriter: { data in
                writeCount += 1
                if writeCount > 1 {
                    defaults.set(data, forKey: UserDefaultsKeys.servers)
                }
            }
        )

        await #expect(throws: ServerManagerError.persistenceReadbackMismatch) {
            try await manager.addServerOrThrow(server, password: "replacement-secret")
        }
        #expect(manager.servers.isEmpty)
        #expect(passwordProbe.values[server.id] == "preexisting-secret")
        let persistedData = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: persistedData).isEmpty)
    }

    @Test func serverPasswordCreateRemovesNewCrossAppRecordsWhenMetadataReadbackFails() async throws {
        let suiteName = "sh.glas.test.server-create-shared-rollback.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode([ServerConfiguration]()), forKey: UserDefaultsKeys.servers)

        let server = migrationServer(host: "shared-rollback.example.com")
        let probe = SharedServerCredentialProbe()
        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            passwordStore: probe.passwordStore,
            serverDataWriter: { _ in }
        )

        await #expect(throws: ServerManagerError.persistenceReadbackMismatch) {
            try await manager.addServerOrThrow(server, password: "must-roll-back")
        }

        let primaryKey = probe.key(
            account: KeychainManager.serverPasswordAccount(for: server.id),
            service: KeychainManager.config.passwordsService
        )
        let sharedKey = probe.key(
            account: try #require(KeychainManager.sharedSSHPasswordAccount(for: server)),
            service: KeychainManager.config.sshPasswordsService
        )
        #expect(probe.values[primaryKey] == nil)
        #expect(probe.values[sharedKey] == nil)
        #expect(manager.servers.isEmpty)
    }

    @Test func failedEndpointEditRestoresExistingGlassDBCredentialExactly() async throws {
        let suiteName = "sh.glas.test.server-edit-shared-rollback.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let original = migrationServer(host: "old.example.com")
        defaults.set(try JSONEncoder().encode([original]), forKey: UserDefaultsKeys.servers)
        var updated = original
        updated.host = "glassdb.example.com"

        let probe = SharedServerCredentialProbe()
        let primaryKey = probe.key(
            account: KeychainManager.serverPasswordAccount(for: original.id),
            service: KeychainManager.config.passwordsService
        )
        let glassDBSharedKey = probe.key(
            account: try #require(KeychainManager.sharedSSHPasswordAccount(for: updated)),
            service: KeychainManager.config.sshPasswordsService
        )
        probe.values[primaryKey] = Data("glas-profile-secret".utf8)
        probe.values[glassDBSharedKey] = Data("glassdb-existing-secret".utf8)

        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            passwordStore: probe.passwordStore,
            serverDataWriter: { _ in }
        )
        manager.servers = [original]

        await #expect(throws: ServerManagerError.persistenceReadbackMismatch) {
            try await manager.updateServerOrThrow(updated, password: "replacement-secret")
        }

        #expect(probe.values[primaryKey] == Data("glas-profile-secret".utf8))
        #expect(probe.values[glassDBSharedKey] == Data("glassdb-existing-secret".utf8))
        #expect(manager.servers == [original])
        let persistedData = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: persistedData) == [original])
    }

    @Test func serverPasswordEditRestoresExactOldSecretWhenMetadataReadbackFails() async throws {
        let suiteName = "sh.glas.test.server-edit-rollback.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let server = migrationServer()
        defaults.set(try JSONEncoder().encode([server]), forKey: UserDefaultsKeys.servers)
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[server.id] = "old-secret"
        var updatedServer = server
        updatedServer.name = "Updated"
        var writeCount = 0
        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            passwordStore: passwordProbe.store,
            serverDataWriter: { data in
                writeCount += 1
                if writeCount > 1 {
                    defaults.set(data, forKey: UserDefaultsKeys.servers)
                }
            }
        )
        manager.servers = [server]

        await #expect(throws: ServerManagerError.persistenceReadbackMismatch) {
            try await manager.updateServerOrThrow(updatedServer, password: "new-secret")
        }
        #expect(manager.servers == [server])
        #expect(passwordProbe.values[server.id] == "old-secret")
        let persistedData = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: persistedData) == [server])
    }

    @Test func passwordAuthChangeRestoresProfileAndSecretWhenDeletionFails() async throws {
        let suiteName = "sh.glas.test.password-auth-rollback.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let server = migrationServer()
        defaults.set(try JSONEncoder().encode([server]), forKey: UserDefaultsKeys.servers)
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[server.id] = "old-secret"
        let baseStore = passwordProbe.store
        var observedCommittedMetadata = false
        let failingStore = ServerPasswordStore(
            retrieve: baseStore.retrieve,
            save: baseStore.save,
            delete: { _ in
                let data = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
                let persisted = try JSONDecoder().decode([ServerConfiguration].self, from: data)
                observedCommittedMetadata = persisted.first?.authMethod == .sshKey
                throw CredentialMigrationProbeError.queryFailure
            }
        )
        let manager = ServerManager(
            loadImmediately: false,
            defaults: defaults,
            passwordStore: failingStore
        )
        manager.servers = [server]
        var updatedServer = server
        updatedServer.authMethod = .sshKey
        updatedServer.sshKeyID = UUID()

        await #expect(throws: CredentialMigrationProbeError.self) {
            try await manager.updateServerOrThrow(updatedServer)
        }
        #expect(observedCommittedMetadata)
        #expect(manager.servers == [server])
        #expect(passwordProbe.values[server.id] == "old-secret")
        #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) == nil)
        let persistedData = try #require(defaults.data(forKey: UserDefaultsKeys.servers))
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: persistedData) == [server])
    }

    @Test func serverDeletionRecoveryPreservesLiveProfileWhenCrashPrecedesMetadataCommit() throws {
        let suiteName = "sh.glas.test.server-delete-precommit.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let server = migrationServer()
        defaults.set(try JSONEncoder().encode([server]), forKey: UserDefaultsKeys.servers)
        let journal = ServerCredentialDeletionJournal(
            version: ServerCredentialDeletionJournal.currentVersion,
            entries: [.init(serverID: server.id, operation: .deleteServer, createdAt: Date())]
        )
        defaults.set(
            try JSONEncoder().encode(journal),
            forKey: ServerManager.credentialDeletionJournalDefaultsKey
        )
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[server.id] = "live-secret"

        let restarted = ServerManager(
            defaults: defaults,
            passwordStore: passwordProbe.store
        )

        #expect(restarted.servers == [server])
        #expect(passwordProbe.values[server.id] == "live-secret")
        #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) == nil)
    }

    @Test func serverDeletionRecoveryRemovesOrphanWhenCrashFollowsMetadataCommit() throws {
        let suiteName = "sh.glas.test.server-delete-postcommit.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let server = migrationServer()
        defaults.set(try JSONEncoder().encode([ServerConfiguration]()), forKey: UserDefaultsKeys.servers)
        let journal = ServerCredentialDeletionJournal(
            version: ServerCredentialDeletionJournal.currentVersion,
            entries: [.init(serverID: server.id, operation: .deleteServer, createdAt: Date())]
        )
        defaults.set(
            try JSONEncoder().encode(journal),
            forKey: ServerManager.credentialDeletionJournalDefaultsKey
        )
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[server.id] = "orphan-secret"

        let restarted = ServerManager(
            defaults: defaults,
            passwordStore: passwordProbe.store
        )

        #expect(restarted.servers.isEmpty)
        #expect(passwordProbe.values[server.id] == nil)
        #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) == nil)
    }

    @Test func passwordAuthChangeRecoveryPreservesSecretWhenCrashPrecedesMetadataCommit() throws {
        let suiteName = "sh.glas.test.password-auth-precommit.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let server = migrationServer()
        defaults.set(try JSONEncoder().encode([server]), forKey: UserDefaultsKeys.servers)
        let journal = ServerCredentialDeletionJournal(
            version: ServerCredentialDeletionJournal.currentVersion,
            entries: [.init(
                serverID: server.id,
                operation: .removePasswordAuthentication,
                createdAt: Date()
            )]
        )
        defaults.set(
            try JSONEncoder().encode(journal),
            forKey: ServerManager.credentialDeletionJournalDefaultsKey
        )
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[server.id] = "live-password"

        let restarted = ServerManager(
            defaults: defaults,
            passwordStore: passwordProbe.store
        )

        #expect(restarted.servers == [server])
        #expect(passwordProbe.values[server.id] == "live-password")
        #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) == nil)
    }

    @Test func passwordAuthChangeRecoveryRemovesOrphanWhenCrashFollowsMetadataCommit() throws {
        let suiteName = "sh.glas.test.password-auth-postcommit.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var server = migrationServer()
        let serverID = server.id
        server.authMethod = .sshKey
        server.sshKeyID = UUID()
        defaults.set(try JSONEncoder().encode([server]), forKey: UserDefaultsKeys.servers)
        let journal = ServerCredentialDeletionJournal(
            version: ServerCredentialDeletionJournal.currentVersion,
            entries: [.init(
                serverID: serverID,
                operation: .removePasswordAuthentication,
                createdAt: Date()
            )]
        )
        defaults.set(
            try JSONEncoder().encode(journal),
            forKey: ServerManager.credentialDeletionJournalDefaultsKey
        )
        let passwordProbe = ServerPasswordProbe()
        passwordProbe.values[serverID] = "orphan-password"

        let restarted = ServerManager(
            defaults: defaults,
            passwordStore: passwordProbe.store
        )

        #expect(restarted.servers == [server])
        #expect(passwordProbe.values[serverID] == nil)
        #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) == nil)
    }

    @Test func serverCredentialRecoveryRetainsSecretWhenCatalogIsAmbiguous() throws {
        let server = migrationServer()
        let fixtures: [(String, Data?)] = [
            ("missing", nil),
            ("malformed", Data("not-json".utf8)),
            ("oversized", Data(repeating: 0, count: ServerManager.maximumServerCatalogBytes + 1))
        ]

        for (label, catalogData) in fixtures {
            let suiteName = "sh.glas.test.server-catalog-\(label).\(UUID().uuidString)"
            let defaults = UserDefaults.forTest(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            if let catalogData {
                defaults.set(catalogData, forKey: UserDefaultsKeys.servers)
            }
            let journal = ServerCredentialDeletionJournal(
                version: ServerCredentialDeletionJournal.currentVersion,
                entries: [.init(
                    serverID: server.id,
                    operation: .deleteServer,
                    createdAt: Date()
                )]
            )
            defaults.set(
                try JSONEncoder().encode(journal),
                forKey: ServerManager.credentialDeletionJournalDefaultsKey
            )
            let passwordProbe = ServerPasswordProbe()
            passwordProbe.values[server.id] = "must-survive"

            let restarted = ServerManager(
                defaults: defaults,
                passwordStore: passwordProbe.store
            )

            #expect(restarted.servers.isEmpty)
            #expect(passwordProbe.values[server.id] == "must-survive")
            #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) != nil)
        }
    }

    @Test func invalidServerCatalogBlocksAddUpdateDeleteAndCredentialAccess() async throws {
        let fixtures: [(String, Any)] = [
            ("malformed", Data("not-json".utf8)),
            ("oversized", Data(repeating: 0, count: ServerManager.maximumServerCatalogBytes + 1)),
            ("wrong-type", "not-data")
        ]

        for (label, persistedValue) in fixtures {
            let suiteName = "sh.glas.test.server-fail-closed-\(label).\(UUID().uuidString)"
            let defaults = UserDefaults.forTest(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(persistedValue, forKey: UserDefaultsKeys.servers)

            var credentialReads = 0
            var credentialWrites = 0
            var credentialDeletes = 0
            var catalogWrites = 0
            let passwordStore = ServerPasswordStore(
                retrieve: { _ in
                    credentialReads += 1
                    throw SecretStoreError.notFound
                },
                save: { _, _ in credentialWrites += 1 },
                delete: { _ in credentialDeletes += 1 }
            )
            let manager = ServerManager(
                defaults: defaults,
                passwordStore: passwordStore,
                serverDataWriter: { _ in catalogWrites += 1 }
            )
            let server = migrationServer()

            #expect(manager.serverCatalogLoadError == .invalidServerCatalog)
            await #expect(throws: ServerManagerError.invalidServerCatalog) {
                try await manager.addServerOrThrow(server, password: "must-not-be-stored")
            }

            // Exercise update and delete from a populated in-memory view to prove
            // the retained failure state, not an empty array, is the mutation gate.
            manager.servers = [server]
            var updated = server
            updated.name = "Must not persist"
            await #expect(throws: ServerManagerError.invalidServerCatalog) {
                try await manager.updateServerOrThrow(updated, password: "must-not-be-stored")
            }
            await #expect(throws: ServerManagerError.invalidServerCatalog) {
                try await manager.deleteServer(server)
            }

            #expect(manager.servers == [server])
            #expect(credentialReads == 0)
            #expect(credentialWrites == 0)
            #expect(credentialDeletes == 0)
            #expect(catalogWrites == 0)
            #expect(defaults.object(forKey: UserDefaultsKeys.servers) as? String
                == persistedValue as? String)
            if let originalData = persistedValue as? Data {
                #expect(defaults.data(forKey: UserDefaultsKeys.servers) == originalData)
            }
            #expect(defaults.data(forKey: ServerManager.credentialDeletionJournalDefaultsKey) == nil)
        }
    }

    @Test func duplicateServerIDsFailClosedBeforeCredentialAccess() throws {
        let fixture = migrationDefaults("duplicate-server-id")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }

        let duplicateID = UUID()
        let first = ServerConfiguration(
            id: duplicateID,
            name: "First",
            host: "first.example.com",
            username: "operator"
        )
        let second = ServerConfiguration(
            id: duplicateID,
            name: "Second",
            host: "second.example.com",
            username: "admin"
        )
        fixture.defaults.set(
            try JSONEncoder().encode([first, second]),
            forKey: UserDefaultsKeys.servers
        )

        var credentialReads = 0
        let manager = ServerManager(
            defaults: fixture.defaults,
            passwordStore: ServerPasswordStore(
                retrieve: { _ in
                    credentialReads += 1
                    return "must-not-be-returned"
                },
                save: { _, _ in },
                delete: { _ in }
            )
        )

        #expect(manager.servers.isEmpty)
        #expect(manager.serverCatalogLoadError == .invalidServerCatalog)
        #expect(throws: ServerManagerError.invalidServerCatalog) {
            try manager.password(for: first)
        }
        #expect(credentialReads == 0)
    }

    @Test @MainActor func serverFormAcceptsAValidPasswordConnection() {
        let input = TerminalServiceDraft.ValidationInput(
            name: "Production",
            host: "example.com",
            port: "22",
            username: "operator",
            authMethod: .password,
            password: " secret with spaces ",
            sshKeyID: nil,
            availableSSHKeyIDs: [],
            usesAppDefaultTerminalSize: true,
            initialTerminalColumns: 0,
            initialTerminalRows: 0
        )

        #expect(TerminalServiceDraft.validationIssues(for: input).isEmpty)
    }

    @Test @MainActor func serverFormReportsFieldSpecificConnectionAndTerminalIssues() {
        let input = TerminalServiceDraft.ValidationInput(
            name: " \n ",
            host: "\t",
            port: "65536",
            username: "  ",
            authMethod: .password,
            password: "",
            sshKeyID: nil,
            availableSSHKeyIDs: [],
            usesAppDefaultTerminalSize: false,
            initialTerminalColumns: 19,
            initialTerminalRows: 7
        )

        let issues = TerminalServiceDraft.validationIssues(for: input)

        #expect(Set(issues.keys) == Set([
            .name,
            .host,
            .port,
            .username,
            .password,
            .terminalSize
        ]))
        #expect(issues[.host] == "Enter the SSH server hostname or IP address.")
        #expect(issues[.port] == "Enter a port from 1 through 65535.")
    }

    @Test @MainActor func serverFormRequiresAnAvailableSSHKey() {
        let availableKeyID = UUID()
        let missingKeyID = UUID()
        let base = TerminalServiceDraft.ValidationInput(
            name: "Production",
            host: "example.com",
            port: "22",
            username: "operator",
            authMethod: .sshKey,
            password: "",
            sshKeyID: missingKeyID,
            availableSSHKeyIDs: [availableKeyID],
            usesAppDefaultTerminalSize: true,
            initialTerminalColumns: 0,
            initialTerminalRows: 0
        )

        #expect(TerminalServiceDraft.validationIssues(for: base)[.sshKey] != nil)

        let available = TerminalServiceDraft.ValidationInput(
            name: base.name,
            host: base.host,
            port: base.port,
            username: base.username,
            authMethod: base.authMethod,
            password: base.password,
            sshKeyID: availableKeyID,
            availableSSHKeyIDs: base.availableSSHKeyIDs,
            usesAppDefaultTerminalSize: base.usesAppDefaultTerminalSize,
            initialTerminalColumns: base.initialTerminalColumns,
            initialTerminalRows: base.initialTerminalRows
        )
        #expect(TerminalServiceDraft.validationIssues(for: available).isEmpty)
    }

    @Test @MainActor func serverFormRejectsLegacyAgentAuthentication() {
        let input = TerminalServiceDraft.ValidationInput(
            name: "Production",
            host: "example.com",
            port: "22",
            username: "operator",
            authMethod: .agent,
            password: "",
            sshKeyID: nil,
            availableSSHKeyIDs: [],
            usesAppDefaultTerminalSize: true,
            initialTerminalColumns: 0,
            initialTerminalRows: 0
        )

        #expect(TerminalServiceDraft.validationIssues(for: input) == [
            .authentication: "Choose Password or SSH Key."
        ])
    }

    @Test @MainActor func serverFormNormalizesEndpointValuesButNotCredentials() {
        #expect(TerminalServiceDraft.normalizedEndpointValue("  cafe\u{301}.example.com \n") == "caf\u{E9}.example.com")
    }

    @Test @MainActor func serverFormReturnKeyFollowsTheVisibleCredentialPath() {
        #expect(TerminalServiceDraft.nextField(after: .name, in: .password) == .host)
        #expect(TerminalServiceDraft.nextField(after: .host, in: .password) == .port)
        #expect(TerminalServiceDraft.nextField(after: .port, in: .password) == .username)
        #expect(TerminalServiceDraft.nextField(after: .username, in: .password) == .password)
        #expect(TerminalServiceDraft.nextField(after: .username, in: .sshKey) == .sshKey)
        #expect(TerminalServiceDraft.nextField(after: .password, in: .password) == nil)
        #expect(TerminalServiceDraft.nextField(after: .sshKey, in: .sshKey) == nil)
    }

    @Test func invalidPerConnectionTerminalGeometryFailsClosed() async throws {
        let fixture = migrationDefaults("invalid-terminal-geometry")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        var server = migrationServer()
        server.initialTerminalColumns = 132
        server.initialTerminalRows = nil

        let manager = ServerManager(
            defaults: fixture.defaults,
            passwordStore: ServerPasswordStore(
                retrieve: { _ in throw SecretStoreError.notFound },
                save: { _, _ in },
                delete: { _ in }
            )
        )

        await #expect(throws: ServerManagerError.invalidServerCatalog) {
            try await manager.addServerOrThrow(server)
        }
        #expect(manager.servers.isEmpty)
        let persisted = try #require(
            fixture.defaults.data(forKey: UserDefaultsKeys.servers)
        )
        #expect(try JSONDecoder().decode([ServerConfiguration].self, from: persisted).isEmpty)
    }

    @Test func invalidSSHKeyCatalogBlocksAddRenameDeleteAndSecretAccess() async throws {
        let fixtures: [(String, Any)] = [
            ("malformed", Data("not-json".utf8)),
            ("oversized", Data(repeating: 0, count: SettingsManager.maximumSSHKeyCatalogBytes + 1)),
            ("wrong-type", ["not": "data"])
        ]

        var encodedKey = ByteBuffer()
        encodedKey.writeString("openssh-key-v1\0")
        for value in ["none", "none", ""] {
            encodedKey.writeInteger(UInt32(value.utf8.count), endianness: .big)
            encodedKey.writeString(value)
        }
        encodedKey.writeInteger(UInt32(1), endianness: .big)
        encodedKey.writeInteger(UInt32(15), endianness: .big)
        encodedKey.writeInteger(UInt32("ssh-ed25519".utf8.count), endianness: .big)
        encodedKey.writeString("ssh-ed25519")
        let privateKey = syntheticOpenSSHPrivateKey(from: encodedKey)

        for (label, persistedValue) in fixtures {
            let suiteName = "sh.glas.test.ssh-key-fail-closed-\(label).\(UUID().uuidString)"
            let defaults = UserDefaults.forTest(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(persistedValue, forKey: UserDefaultsKeys.sshKeys)

            var secretReads = 0
            var secretWrites = 0
            var secretDeletes = 0
            var catalogWrites = 0
            let lifecycle = SSHKeyLifecycleStore(
                retrieve: { _ in
                    secretReads += 1
                    return nil
                },
                delete: { _ in secretDeletes += 1 },
                restore: { _, _ in secretWrites += 1 },
                addIfAbsent: { _, _ in
                    secretWrites += 1
                    return true
                }
            )
            let settings = SettingsManager(
                settingsDefaults: defaults,
                sshKeyDefaults: defaults,
                sshKeyLifecycleStore: lifecycle,
                sshKeyCatalogWriter: { _ in catalogWrites += 1 }
            )
            let existingKey = StoredSSHKey(
                name: "Retained",
                algorithm: "Ed25519",
                storageKind: .imported,
                algorithmKind: .ed25519,
                migrationState: .migrated
            )

            #expect(settings.sshKeyCatalogLoadError != nil)
            #expect(throws: SettingsPersistenceError.self) {
                try settings.addSSHKey(
                    name: "Must not persist",
                    privateKey: privateKey,
                    passphrase: nil
                )
            }

            settings.sshKeys = [existingKey]
            #expect(throws: SettingsPersistenceError.self) {
                try settings.renameSSHKeyOrThrow(existingKey.id, name: "Must not rename")
            }
            await #expect(throws: SettingsPersistenceError.self) {
                try await settings.deleteSSHKey(existingKey.id)
            }

            #expect(settings.sshKeys == [existingKey])
            #expect(secretReads == 0)
            #expect(secretWrites == 0)
            #expect(secretDeletes == 0)
            #expect(catalogWrites == 0)
            if let originalData = persistedValue as? Data {
                #expect(defaults.data(forKey: UserDefaultsKeys.sshKeys) == originalData)
            } else {
                #expect(defaults.object(forKey: UserDefaultsKeys.sshKeys) as? [String: String]
                    == persistedValue as? [String: String])
            }
            #expect(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal) == nil)
        }
    }

    @Test func importedSSHKeyCreationVerifiesCatalogAndDeletesSecretOnRollback() throws {
        let suiteName = "sh.glas.test.ssh-key-create-rollback.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode([StoredSSHKey]()), forKey: UserDefaultsKeys.sshKeys)

        var encodedKey = ByteBuffer()
        encodedKey.writeString("openssh-key-v1\0")
        for value in ["none", "none", ""] {
            encodedKey.writeInteger(UInt32(value.utf8.count), endianness: .big)
            encodedKey.writeString(value)
        }
        encodedKey.writeInteger(UInt32(1), endianness: .big)
        encodedKey.writeInteger(UInt32(15), endianness: .big)
        encodedKey.writeInteger(UInt32("ssh-ed25519".utf8.count), endianness: .big)
        encodedKey.writeString("ssh-ed25519")
        let privateKey = syntheticOpenSSHPrivateKey(from: encodedKey)

        var storedMaterial: SSHKeyMaterial?
        let lifecycle = SSHKeyLifecycleStore(
            retrieve: { _ in storedMaterial },
            delete: { _ in storedMaterial = nil },
            restore: { _, material in storedMaterial = material },
            addIfAbsent: { _, material in
                guard case nil = storedMaterial else { return false }
                storedMaterial = material
                return true
            }
        )
        var catalogWrites = 0
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycle,
            sshKeyCatalogWriter: { data in
                catalogWrites += 1
                defaults.set(
                    catalogWrites == 1 ? Data("malformed".utf8) : data,
                    forKey: UserDefaultsKeys.sshKeys
                )
            }
        )

        #expect(throws: SettingsPersistenceError.self) {
            try settings.addSSHKey(name: "Rollback", privateKey: privateKey, passphrase: nil)
        }
        #expect(settings.sshKeys.isEmpty)
        #expect(storedMaterial == nil)
        #expect(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal) == nil)
        let persisted = try #require(defaults.data(forKey: UserDefaultsKeys.sshKeys))
        #expect(try JSONDecoder().decode([StoredSSHKey].self, from: persisted).isEmpty)
    }

    @Test func sshKeyDeletionPersistsMetadataFirstAndRestoresSecretAndReferencesOnFailure() async throws {
        let keySuiteName = "sh.glas.test.ssh-key-delete.\(UUID().uuidString)"
        let serverSuiteName = "sh.glas.test.ssh-key-server-delete.\(UUID().uuidString)"
        let keyDefaults = UserDefaults.forTest(suiteName: keySuiteName)!
        let serverDefaults = UserDefaults.forTest(suiteName: serverSuiteName)!
        defer {
            keyDefaults.removePersistentDomain(forName: keySuiteName)
            serverDefaults.removePersistentDomain(forName: serverSuiteName)
        }

        let keyID = UUID()
        let key = StoredSSHKey(
            id: keyID,
            name: "Imported",
            algorithm: "Ed25519",
            storageKind: .imported,
            algorithmKind: .ed25519,
            migrationState: .migrated
        )
        var server = migrationServer()
        server.authMethod = .sshKey
        server.sshKeyID = keyID
        let serverManager = ServerManager(loadImmediately: false, defaults: serverDefaults)
        serverManager.servers = [server]
        try await serverManager.persistServersOrThrow()
        keyDefaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)

        let material = SSHKeyMaterial(
            privateKey: SecureBytes(Data("private-key".utf8)),
            passphrase: SecureBytes(Data("passphrase".utf8))
        )
        var observedMetadataRemoval = false
        var restoredSecret = false
        var storedMaterial: SSHKeyMaterial? = material
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in storedMaterial },
            delete: { _ in
                let keyData = try #require(keyDefaults.data(forKey: UserDefaultsKeys.sshKeys))
                let persistedKeys = try JSONDecoder().decode([StoredSSHKey].self, from: keyData)
                let serverData = try #require(serverDefaults.data(forKey: UserDefaultsKeys.servers))
                let persistedServers = try JSONDecoder().decode([ServerConfiguration].self, from: serverData)
                observedMetadataRemoval = persistedKeys.isEmpty && persistedServers.first?.sshKeyID == nil
                storedMaterial = nil
                throw CredentialMigrationProbeError.queryFailure
            },
            restore: { _, restored in
                restoredSecret = true
                storedMaterial = restored
            },
            addIfAbsent: { _, restored in
                guard case nil = storedMaterial else { return false }
                restoredSecret = true
                storedMaterial = restored
                return true
            }
        )
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: keyDefaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        settings.sshKeys = [key]

        await #expect(throws: CredentialMigrationProbeError.self) {
            try await settings.deleteSSHKey(keyID, serverManager: serverManager)
        }
        #expect(observedMetadataRemoval)
        #expect(restoredSecret)
        #expect(storedMaterial?.privateKey.toData() == material.privateKey.toData())
        #expect(storedMaterial?.passphrase?.toData() == material.passphrase?.toData())
        #expect(settings.sshKeys == [key])
        #expect(serverManager.servers.first?.sshKeyID == keyID)
        let journalData = try #require(keyDefaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal))
        let journal = try JSONDecoder().decode(SSHKeyDeletionJournal.self, from: journalData)
        #expect(journal.entries.first?.phase == .recoveryRequired)
        #expect(!String(decoding: journalData, as: UTF8.self).contains("private-key"))
        #expect(!String(decoding: journalData, as: UTF8.self).contains("passphrase"))
    }

    @Test func sshKeyDeletionJournalRollsForwardPartialArtifactsAfterSimulatedRestart() throws {
        let suiteName = "sh.glas.test.ssh-key-delete-restart.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Interrupted",
            algorithm: "Ed25519",
            storageKind: .imported,
            algorithmKind: .ed25519,
            migrationState: .migrated
        )
        defaults.set(try JSONEncoder().encode([StoredSSHKey]()), forKey: UserDefaultsKeys.sshKeys)
        defaults.set(try JSONEncoder().encode(SSHKeyDeletionJournal(
            version: SSHKeyDeletionJournal.currentVersion,
            entries: [.init(
                key: key,
                referencedServerIDs: [],
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                // Simulate interruption after metadata committed but before the
                // journal phase write; persisted metadata remains authoritative.
                phase: .prepared,
                recoveryMessage: nil
            )]
        )), forKey: UserDefaultsKeys.sshKeyDeletionJournal)

        var hasArtifacts = true
        var deleteCount = 0
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in nil },
            delete: { _ in
                deleteCount += 1
                hasArtifacts = false
            },
            restore: { _, _ in },
            addIfAbsent: { _, _ in false },
            hasAnyArtifacts: { _ in hasArtifacts }
        )

        let restarted = SettingsManager(
            loadImmediately: true,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )

        #expect(deleteCount == 1)
        #expect(!hasArtifacts)
        #expect(restarted.sshKeys.isEmpty)
        #expect(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal) == nil)
        #expect(restarted.sshKeyDeletionRecoveryError == nil)
    }

    @Test func sshKeyDeletionRetainsActionableJournalWhenSecretRestoreReadbackDiffers() async throws {
        let suiteName = "sh.glas.test.ssh-key-delete-restore-mismatch.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Restore mismatch",
            algorithm: "Ed25519",
            storageKind: .imported,
            algorithmKind: .ed25519,
            migrationState: .migrated
        )
        defaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)
        let original = SSHKeyMaterial(
            privateKey: SecureBytes(Data("original-private-key".utf8)),
            passphrase: SecureBytes(Data("original-passphrase".utf8))
        )
        let mismatched = SSHKeyMaterial(
            privateKey: SecureBytes(Data("different-private-key".utf8)),
            passphrase: SecureBytes(Data("original-passphrase".utf8))
        )
        var storedMaterial: SSHKeyMaterial? = original
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in storedMaterial },
            delete: { _ in
                storedMaterial = nil
                throw CredentialMigrationProbeError.queryFailure
            },
            restore: { _, _ in storedMaterial = mismatched },
            addIfAbsent: { _, _ in
                guard case nil = storedMaterial else { return false }
                storedMaterial = mismatched
                return true
            }
        )
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        settings.sshKeys = [key]

        do {
            try await settings.deleteSSHKey(key.id)
            Issue.record("Secret restoration with mismatched readback must fail")
        } catch let error as SettingsPersistenceError {
            if case .rollbackFailed = error {
                // Expected: the restored bytes did not exactly match the original material.
            } else {
                Issue.record("Expected rollbackFailed, received \(error)")
            }
        }

        #expect(settings.sshKeyDeletionRecoveryError == SettingsPersistenceError.rollbackFailed.localizedDescription)
        #expect(settings.sshKeys == [key])
        let journalData = try #require(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal))
        let journal = try JSONDecoder().decode(SSHKeyDeletionJournal.self, from: journalData)
        #expect(journal.entries.first?.phase == .recoveryRequired)
        #expect(journal.entries.first?.recoveryMessage == SettingsPersistenceError.rollbackFailed.localizedDescription)
        #expect(!String(decoding: journalData, as: UTF8.self).contains("original-private-key"))
        #expect(!String(decoding: journalData, as: UTF8.self).contains("original-passphrase"))

        let restarted = SettingsManager(
            loadImmediately: true,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        #expect(restarted.sshKeyDeletionRecoveryError == SettingsPersistenceError.rollbackFailed.localizedDescription)
        let retainedData = try #require(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal))
        let retainedJournal = try JSONDecoder().decode(SSHKeyDeletionJournal.self, from: retainedData)
        #expect(retainedJournal.entries.first?.phase == .recoveryRequired)
        #expect(storedMaterial?.privateKey.toData() == mismatched.privateKey.toData())
    }

    @Test func sshKeyDeletionRollbackPreservesConcurrentSecretReplacement() async throws {
        let suiteName = "sh.glas.test.ssh-key-delete-concurrent-replacement.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Concurrent replacement",
            algorithm: "Ed25519",
            storageKind: .imported,
            algorithmKind: .ed25519,
            migrationState: .migrated
        )
        defaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)
        let original = SSHKeyMaterial(
            privateKey: SecureBytes(Data("original-private-key".utf8)),
            passphrase: nil
        )
        let replacement = SSHKeyMaterial(
            privateKey: SecureBytes(Data("concurrent-private-key".utf8)),
            passphrase: nil
        )
        var storedMaterial: SSHKeyMaterial? = original
        var restoreCount = 0
        var atomicAddAttemptCount = 0
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in storedMaterial },
            delete: { _ in
                storedMaterial = nil
                throw CredentialMigrationProbeError.queryFailure
            },
            restore: { _, restored in
                restoreCount += 1
                storedMaterial = restored
            },
            addIfAbsent: { _, restored in
                atomicAddAttemptCount += 1
                // Simulate another process winning the atomic SecItemAdd race.
                storedMaterial = replacement
                _ = restored
                return false
            }
        )
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        settings.sshKeys = [key]

        await #expect(throws: SettingsPersistenceError.self) {
            try await settings.deleteSSHKey(key.id)
        }
        #expect(restoreCount == 0)
        #expect(atomicAddAttemptCount == 1)
        #expect(storedMaterial?.privateKey.toData() == replacement.privateKey.toData())
        #expect(settings.sshKeyDeletionRecoveryError == SettingsPersistenceError.rollbackFailed.localizedDescription)
        let journalData = try #require(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal))
        let journal = try JSONDecoder().decode(SSHKeyDeletionJournal.self, from: journalData)
        #expect(journal.entries.first?.phase == .recoveryRequired)
    }

    @Test func legacySecureEnclaveDeletionRollbackNeverDowngradesToImportedStorage() async throws {
        let suiteName = "sh.glas.test.ssh-key-delete-legacy-se.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Legacy Secure Enclave",
            algorithm: "ECDSA P-256",
            storageKind: .secureEnclave,
            algorithmKind: .ecdsaP256,
            migrationState: .migrated
        )
        defaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)
        let original = SSHKeyMaterial(
            privateKey: SecureBytes(Data("SECURE_ENCLAVE_P256:bGVnYWN5LXJhdy1rZXk=".utf8)),
            passphrase: nil
        )
        var storedMaterial: SSHKeyMaterial? = original
        var atomicAddAttemptCount = 0
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in storedMaterial },
            delete: { _ in
                storedMaterial = nil
                throw CredentialMigrationProbeError.queryFailure
            },
            restore: { _, restored in storedMaterial = restored },
            addIfAbsent: { _, restored in
                atomicAddAttemptCount += 1
                storedMaterial = restored
                return true
            }
        )
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        settings.sshKeys = [key]

        await #expect(throws: SettingsPersistenceError.self) {
            try await settings.deleteSSHKey(key.id)
        }
        #expect(atomicAddAttemptCount == 0)
        #expect(storedMaterial == nil)
        #expect(settings.sshKeyDeletionRecoveryError == SettingsPersistenceError.rollbackFailed.localizedDescription)
        let journalData = try #require(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal))
        let journal = try JSONDecoder().decode(SSHKeyDeletionJournal.self, from: journalData)
        #expect(journal.entries.first?.phase == .recoveryRequired)
    }

    @Test func legacySecureEnclaveDeletionAcceptsOnlyVerifiedHardwareBackedRecovery() async throws {
        let suiteName = "sh.glas.test.ssh-key-delete-legacy-se-verified.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Verified Legacy Secure Enclave",
            algorithm: "ECDSA P-256",
            storageKind: .secureEnclave,
            algorithmKind: .ecdsaP256,
            migrationState: .migrated
        )
        defaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)
        let original = SSHKeyMaterial(
            privateKey: SecureBytes(Data("SECURE_ENCLAVE_P256:dmVyaWZpZWQ=".utf8)),
            passphrase: nil
        )
        var storedMaterial: SSHKeyMaterial? = original
        var provenanceVerificationCount = 0
        var atomicAddAttemptCount = 0
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in storedMaterial },
            delete: { _ in throw CredentialMigrationProbeError.queryFailure },
            restore: { _, restored in storedMaterial = restored },
            addIfAbsent: { _, restored in
                atomicAddAttemptCount += 1
                storedMaterial = restored
                return true
            },
            verifiesLegacySecureEnclaveBacking: { _, material in
                provenanceVerificationCount += 1
                return material.privateKey.toData() == original.privateKey.toData()
            }
        )
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        settings.sshKeys = [key]

        await #expect(throws: CredentialMigrationProbeError.self) {
            try await settings.deleteSSHKey(key.id)
        }
        #expect(provenanceVerificationCount == 1)
        #expect(atomicAddAttemptCount == 0)
        #expect(storedMaterial?.privateKey.toData() == original.privateKey.toData())
        #expect(settings.sshKeys == [key])
        #expect(settings.sshKeyDeletionRecoveryError?.contains("restored and verified") == true)
    }

    @Test func sshKeyDeletionRemovesPartialArtifactsWhenMaterialRetrievalIsNil() async throws {
        let suiteName = "sh.glas.test.ssh-key-delete-partial.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Partial representation",
            algorithm: "Ed25519",
            storageKind: .imported,
            algorithmKind: .ed25519,
            migrationState: .migrated
        )
        defaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)
        var hasArtifacts = true
        var deleteCount = 0
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in nil },
            delete: { _ in
                deleteCount += 1
                hasArtifacts = false
            },
            restore: { _, _ in },
            addIfAbsent: { _, _ in false },
            hasAnyArtifacts: { _ in hasArtifacts }
        )
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        settings.sshKeys = [key]

        try await settings.deleteSSHKey(key.id)

        #expect(deleteCount == 1)
        #expect(!hasArtifacts)
        #expect(settings.sshKeys.isEmpty)
        #expect(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal) == nil)
    }

    @Test func sshKeyDeletionFailureWithUnrecoverablePartialArtifactsFailsClosed() async throws {
        let suiteName = "sh.glas.test.ssh-key-delete-partial-failure.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Unrecoverable partial representation",
            algorithm: "ECDSA P-256",
            storageKind: .secureEnclave,
            algorithmKind: .ecdsaP256,
            migrationState: .migrated
        )
        defaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)
        var hasArtifacts = true
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in nil },
            delete: { _ in
                hasArtifacts = false
                throw CredentialMigrationProbeError.queryFailure
            },
            restore: { _, _ in },
            addIfAbsent: { _, _ in false },
            hasAnyArtifacts: { _ in hasArtifacts }
        )
        let settings = SettingsManager(
            loadImmediately: false,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )
        settings.sshKeys = [key]

        await #expect(throws: SettingsPersistenceError.self) {
            try await settings.deleteSSHKey(key.id)
        }

        #expect(!hasArtifacts)
        #expect(settings.sshKeys == [key])
        #expect(settings.sshKeyDeletionRecoveryError == SettingsPersistenceError.rollbackFailed.localizedDescription)
        let journalData = try #require(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal))
        let journal = try JSONDecoder().decode(SSHKeyDeletionJournal.self, from: journalData)
        #expect(journal.entries.first?.phase == .recoveryRequired)
        #expect(journal.entries.first?.recoveryMessage == SettingsPersistenceError.rollbackFailed.localizedDescription)
    }

    @Test func sshKeyDeletionJournalAbortsBeforeMetadataCommitAndPreservesSecret() throws {
        let suiteName = "sh.glas.test.ssh-key-delete-ambiguous.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = StoredSSHKey(
            id: UUID(),
            name: "Ambiguous",
            algorithm: "Ed25519",
            storageKind: .imported,
            algorithmKind: .ed25519,
            migrationState: .migrated
        )
        var server = migrationServer()
        server.authMethod = .sshKey
        server.sshKeyID = key.id
        defaults.set(try JSONEncoder().encode([key]), forKey: UserDefaultsKeys.sshKeys)
        defaults.set(try JSONEncoder().encode([server]), forKey: UserDefaultsKeys.servers)
        defaults.set(try JSONEncoder().encode(SSHKeyDeletionJournal(
            version: SSHKeyDeletionJournal.currentVersion,
            entries: [.init(
                key: key,
                referencedServerIDs: [server.id],
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                phase: .prepared,
                recoveryMessage: nil
            )]
        )), forKey: UserDefaultsKeys.sshKeyDeletionJournal)
        let material = SSHKeyMaterial(
            privateKey: SecureBytes(Data("still-present".utf8)),
            passphrase: nil
        )
        var deleteCount = 0
        let lifecycleStore = SSHKeyLifecycleStore(
            retrieve: { _ in material },
            delete: { _ in deleteCount += 1 },
            restore: { _, _ in },
            addIfAbsent: { _, _ in false }
        )

        let restarted = SettingsManager(
            loadImmediately: true,
            sshKeyDefaults: defaults,
            sshKeyLifecycleStore: lifecycleStore
        )

        #expect(restarted.sshKeys == [key])
        #expect(deleteCount == 0)
        #expect(restarted.sshKeyDeletionRecoveryError == nil)
        #expect(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal) == nil)
    }

    @Test func sshKeyDeletionJournalTreatsMissingOrMalformedCatalogAsAmbiguous() throws {
        for catalogData in [nil, Data("{".utf8)] as [Data?] {
            let suiteName = "sh.glas.test.ssh-key-delete-catalog-ambiguous.\(UUID().uuidString)"
            let defaults = UserDefaults.forTest(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let key = StoredSSHKey(
                id: UUID(),
                name: "Catalog ambiguity",
                algorithm: "Ed25519",
                storageKind: .imported,
                algorithmKind: .ed25519,
                migrationState: .migrated
            )
            if let catalogData {
                defaults.set(catalogData, forKey: UserDefaultsKeys.sshKeys)
            }
            defaults.set(try JSONEncoder().encode(SSHKeyDeletionJournal(
                version: SSHKeyDeletionJournal.currentVersion,
                entries: [.init(
                    key: key,
                    referencedServerIDs: [],
                    createdAt: Date(),
                    phase: .prepared,
                    recoveryMessage: nil
                )]
            )), forKey: UserDefaultsKeys.sshKeyDeletionJournal)
            let material = SSHKeyMaterial(
                privateKey: SecureBytes(Data("must-survive".utf8)),
                passphrase: nil
            )
            var deleteCount = 0
            let lifecycleStore = SSHKeyLifecycleStore(
                retrieve: { _ in material },
                delete: { _ in deleteCount += 1 },
                restore: { _, _ in },
                addIfAbsent: { _, _ in false }
            )

            let restarted = SettingsManager(
                loadImmediately: true,
                sshKeyDefaults: defaults,
                sshKeyLifecycleStore: lifecycleStore
            )

            #expect(deleteCount == 0)
            #expect(restarted.sshKeyDeletionRecoveryError != nil)
            #expect(defaults.data(forKey: UserDefaultsKeys.sshKeyDeletionJournal) != nil)
        }
    }

    private func trustedHostEntry(
        host: String = "example.com",
        port: Int = 22,
        algorithm: String = "ssh-ed25519",
        key: String = "legacy-host-key",
        addedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> TrustedHostKeyEntry {
        let keyData = Data(key.utf8)
        let canonicalFingerprint = PinnedSSHHostKey.sha256Fingerprint(for: keyData)
        let unpaddedFingerprint = String(canonicalFingerprint.dropFirst("SHA256:".count))
        let legacyFingerprint = unpaddedFingerprint
            + String(repeating: "=", count: (4 - unpaddedFingerprint.count % 4) % 4)
        return TrustedHostKeyEntry(
            host: host,
            port: port,
            algorithm: algorithm,
            fingerprintSHA256: legacyFingerprint,
            keyDataBase64: keyData.base64EncodedString(),
            addedAt: addedAt
        )
    }

    private func migrationDefaults(_ suffix: String) -> (name: String, defaults: UserDefaults) {
        let name = "sh.glas.test.host-trust.\(suffix).\(UUID().uuidString)"
        return (name, UserDefaults.forTest(suiteName: name)!)
    }

    private func migrationReport(from defaults: UserDefaults) throws -> HostTrustMigrationReport {
        let data = try #require(defaults.data(forKey: UserDefaultsKeys.hostTrustMigrationReport))
        return try JSONDecoder().decode(HostTrustMigrationReport.self, from: data)
    }

    @Test func hostTrustMigrationCandidateValidationRejectsMalformedFields() {
        let valid = trustedHostEntry()
        let malformedEntries = [
            TrustedHostKeyEntry(
                host: valid.host,
                port: valid.port,
                algorithm: valid.algorithm,
                fingerprintSHA256: valid.fingerprintSHA256,
                keyDataBase64: "not base64",
                addedAt: valid.addedAt
            ),
            TrustedHostKeyEntry(
                host: valid.host,
                port: valid.port,
                algorithm: valid.algorithm,
                fingerprintSHA256: valid.fingerprintSHA256,
                keyDataBase64: "",
                addedAt: valid.addedAt
            ),
            TrustedHostKeyEntry(
                host: "   ",
                port: valid.port,
                algorithm: valid.algorithm,
                fingerprintSHA256: valid.fingerprintSHA256,
                keyDataBase64: valid.keyDataBase64,
                addedAt: valid.addedAt
            ),
            TrustedHostKeyEntry(
                host: valid.host,
                port: 0,
                algorithm: valid.algorithm,
                fingerprintSHA256: valid.fingerprintSHA256,
                keyDataBase64: valid.keyDataBase64,
                addedAt: valid.addedAt
            ),
            TrustedHostKeyEntry(
                host: valid.host,
                port: valid.port,
                algorithm: valid.algorithm,
                fingerprintSHA256: "SHA256:not-the-key",
                keyDataBase64: valid.keyDataBase64,
                addedAt: valid.addedAt
            ),
        ]

        for entry in malformedEntries {
            #expect(throws: (any Error).self) {
                _ = try KeychainManager.pinnedHostKey(from: entry)
            }
        }
    }

    @Test @MainActor func hostTrustMigrationMigratesGlobalOnlySource() async throws {
        let fixture = migrationDefaults("global")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let entry = trustedHostEntry()
        fixture.defaults.set(
            try JSONEncoder().encode([entry]),
            forKey: UserDefaultsKeys.trustedHostKeys
        )
        let probe = HostTrustStoreProbe()

        let manager = ServerManager(
            loadImmediately: false,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        manager.loadServersIfNeeded()
        await manager.legacyHostTrustMigration?.value

        #expect(manager.servers.isEmpty)
        #expect(probe.records.count == 1)
        #expect(fixture.defaults.data(forKey: UserDefaultsKeys.trustedHostKeys) == nil)
        #expect(
            fixture.defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion)
                == ServerManager.currentHostTrustMigrationVersion
        )
        let report = try migrationReport(from: fixture.defaults)
        #expect(report.state == .completed)
        #expect(report.globalSourceCount == 1)
        #expect(report.serverSourceCount == 0)
        #expect(report.uniqueCandidateCount == 1)
        #expect(report.verifiedCount == 1)
    }

    @Test @MainActor func hostTrustMigrationCombinesAndDeduplicatesSources() async throws {
        let fixture = migrationDefaults("combined")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let entry = trustedHostEntry()
        fixture.defaults.set(
            try JSONEncoder().encode([entry]),
            forKey: UserDefaultsKeys.trustedHostKeys
        )
        var server = ServerConfiguration(
            name: "Legacy",
            host: entry.host,
            port: entry.port,
            username: "user"
        )
        server.trustedHostKeys = [entry]
        fixture.defaults.set(
            try JSONEncoder().encode([server]),
            forKey: UserDefaultsKeys.servers
        )
        let probe = HostTrustStoreProbe()

        let manager = ServerManager(
            loadImmediately: false,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        manager.loadServersIfNeeded()
        await manager.legacyHostTrustMigration?.value

        #expect(probe.saveCount == 1)
        #expect(probe.records.count == 1)
        #expect(manager.servers.first?.trustedHostKeys == nil)
        let persistedData = try #require(fixture.defaults.data(forKey: UserDefaultsKeys.servers))
        let persistedServers = try JSONDecoder().decode([ServerConfiguration].self, from: persistedData)
        #expect(persistedServers.first?.trustedHostKeys == nil)
        let report = try migrationReport(from: fixture.defaults)
        #expect(report.globalSourceCount == 1)
        #expect(report.serverSourceCount == 1)
        #expect(report.uniqueCandidateCount == 1)
        #expect(report.duplicateCount == 1)
    }

    @Test @MainActor func hostTrustMigrationRetainsInvalidLegacySources() async throws {
        let fixture = migrationDefaults("invalid")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let invalid = TrustedHostKeyEntry(
            host: "example.com",
            port: 22,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:not-the-key",
            keyDataBase64: "not base64",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let globalData = try JSONEncoder().encode([invalid])
        fixture.defaults.set(globalData, forKey: UserDefaultsKeys.trustedHostKeys)
        var server = ServerConfiguration(
            name: "Legacy",
            host: invalid.host,
            port: invalid.port,
            username: "user"
        )
        server.trustedHostKeys = [invalid]
        let serverData = try JSONEncoder().encode([server])
        fixture.defaults.set(serverData, forKey: UserDefaultsKeys.servers)
        let probe = HostTrustStoreProbe()

        let manager = ServerManager(
            loadImmediately: false,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        manager.loadServersIfNeeded()
        await manager.legacyHostTrustMigration?.value

        #expect(probe.saveCount == 0)
        #expect(fixture.defaults.data(forKey: UserDefaultsKeys.trustedHostKeys) == globalData)
        #expect(fixture.defaults.data(forKey: UserDefaultsKeys.servers) == serverData)
        #expect(fixture.defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion) == 0)
        #expect(manager.servers.first?.trustedHostKeys == [invalid])
        #expect(try migrationReport(from: fixture.defaults).state == .failed)
    }

    @Test @MainActor func hostTrustMigrationRetainsSourcesWhenStoreFails() async throws {
        let fixture = migrationDefaults("store-failure")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let entry = trustedHostEntry()
        let globalData = try JSONEncoder().encode([entry])
        fixture.defaults.set(globalData, forKey: UserDefaultsKeys.trustedHostKeys)
        let probe = HostTrustStoreProbe()
        probe.failSaves = true

        let manager = ServerManager(
            loadImmediately: false,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        manager.loadServersIfNeeded()
        await manager.legacyHostTrustMigration?.value

        #expect(probe.saveCount == 1)
        #expect(fixture.defaults.data(forKey: UserDefaultsKeys.trustedHostKeys) == globalData)
        #expect(fixture.defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion) == 0)
        #expect(try migrationReport(from: fixture.defaults).state == .failed)
    }

    @Test @MainActor func hostTrustMigrationRetainsSourcesOnExistingKeyConflict() async throws {
        let fixture = migrationDefaults("key-conflict")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let legacyEntry = trustedHostEntry(key: "legacy-key")
        let globalData = try JSONEncoder().encode([legacyEntry])
        fixture.defaults.set(globalData, forKey: UserDefaultsKeys.trustedHostKeys)
        let existingEntry = trustedHostEntry(key: "different-current-key")
        let existingRecord = try KeychainManager.pinnedHostKey(from: existingEntry)
        let probe = HostTrustStoreProbe()
        probe.records[existingRecord.storageAccount] = existingRecord

        let manager = ServerManager(
            loadImmediately: false,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        manager.loadServersIfNeeded()
        await manager.legacyHostTrustMigration?.value

        #expect(probe.saveCount == 0)
        #expect(fixture.defaults.data(forKey: UserDefaultsKeys.trustedHostKeys) == globalData)
        #expect(fixture.defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion) == 0)
        #expect(try migrationReport(from: fixture.defaults).failureCode == "conflicting-keys")
    }

    @Test @MainActor func hostTrustMigrationRetainsSourcesWhenReadbackFails() async throws {
        let fixture = migrationDefaults("readback-failure")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let entry = trustedHostEntry()
        let globalData = try JSONEncoder().encode([entry])
        fixture.defaults.set(globalData, forKey: UserDefaultsKeys.trustedHostKeys)
        let probe = HostTrustStoreProbe()
        probe.omitRecordsOnReadback = true

        let manager = ServerManager(
            loadImmediately: false,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        manager.loadServersIfNeeded()
        await manager.legacyHostTrustMigration?.value

        #expect(probe.saveCount == 1)
        #expect(fixture.defaults.data(forKey: UserDefaultsKeys.trustedHostKeys) == globalData)
        #expect(fixture.defaults.integer(forKey: UserDefaultsKeys.hostTrustMigrationVersion) == 0)
        #expect(try migrationReport(from: fixture.defaults).failureCode == "keychain-readback-mismatch")
    }

    @Test @MainActor func hostTrustMigrationIsIdempotentAfterCompletion() async throws {
        let fixture = migrationDefaults("idempotent")
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let entry = trustedHostEntry()
        fixture.defaults.set(
            try JSONEncoder().encode([entry]),
            forKey: UserDefaultsKeys.trustedHostKeys
        )
        let probe = HostTrustStoreProbe()

        // The migration now runs in a task the manager holds, so both managers have to be kept
        // alive long enough to be awaited rather than discarded at the call.
        let first = ServerManager(
            loadImmediately: true,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        await first.legacyHostTrustMigration?.value
        let firstSaveCount = probe.saveCount
        let firstReport = try migrationReport(from: fixture.defaults)

        let second = ServerManager(
            loadImmediately: true,
            defaults: fixture.defaults,
            hostTrustStore: probe.store
        )
        await second.legacyHostTrustMigration?.value

        #expect(firstSaveCount == 1)
        #expect(probe.saveCount == firstSaveCount)
        #expect(try migrationReport(from: fixture.defaults) == firstReport)
    }

    @Test @MainActor func serverManagerStartsEmpty() {
        let manager = ServerManager(loadImmediately: false)
        #expect(manager.servers.isEmpty)
    }

    @Test @MainActor func serverManagerAddAndRemove() {
        let manager = ServerManager(loadImmediately: false)
        let server = ServerConfiguration(
            name: "Test Server",
            host: "test.example.com",
            port: 22,
            username: "testuser"
        )

        manager.servers.append(server)
        #expect(manager.servers.count == 1)
        #expect(manager.server(for: server.id)?.name == "Test Server")

        manager.servers.removeAll { $0.id == server.id }
        #expect(manager.servers.isEmpty)
        #expect(manager.server(for: server.id) == nil)
    }

    @Test @MainActor func serverManagerToggleFavorite() async {
        let suiteName = "sh.glas.test.server-manager.toggle-favorite.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ServerManager(loadImmediately: false, defaults: defaults)
        #if os(macOS)
        let username = NSUserName()
        #else
        let username = "user"
        #endif
        var server = ServerConfiguration(
            name: "Localhost",
            host: "localhost",
            port: 22,
            username: username
        )
        server.isFavorite = false
        manager.servers.append(server)

        await manager.toggleFavorite(server)
        #expect(manager.servers.first?.isFavorite == true)

        await manager.toggleFavorite(manager.servers.first!)
        #expect(manager.servers.first?.isFavorite == false)
    }

    @Test @MainActor func serverManagerUpdateServer() async {
        let suiteName = "sh.glas.test.server-manager.update.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ServerManager(loadImmediately: false, defaults: defaults)
        let server = ServerConfiguration(
            name: "Original",
            host: "original.example.com",
            port: 22,
            username: "user"
        )
        manager.servers.append(server)

        var updated = server
        updated.name = "Updated"
        updated.host = "updated.example.com"
        await manager.updateServer(updated)

        #expect(manager.servers.first?.name == "Updated")
        #expect(manager.servers.first?.host == "updated.example.com")
        #expect(defaults.data(forKey: UserDefaultsKeys.servers) != nil)
    }

    // MARK: - Connection Library Projection Tests

    @Test func connectionLibraryProjectionDeduplicatesServersAndSearchesWorkgroups() {
        let shared = UUID()
        let servers = [
            ServerConfiguration(id: shared, name: "alpha", host: "a.example", port: 22, username: "u"),
            ServerConfiguration(id: shared, name: "alpha duplicate", host: "a.example", port: 22, username: "u"),
            ServerConfiguration(name: "beta", host: "b.example", port: 22, username: "u"),
        ]
        var preset = LayoutPreset(name: "Ops", sessionIntents: [])
        preset.sessionIntents = [.init(kind: .ssh, serverID: servers[2].id, label: "db-primary")]
        let projection = ConnectionLibraryProjection(servers: servers, workgroups: [preset], networkIsConfigured: false)
        #expect(projection.servers.map(\.name) == ["alpha", "beta"])
        #expect(projection.workgroups(matching: "").count == 1)
        #expect(projection.workgroups(matching: "ops").count == 1)
        #expect(projection.workgroups(matching: "primary").count == 1, "session labels are searched")
        #expect(projection.workgroups(matching: "nothing").isEmpty)
    }

    @Test @MainActor func tailscaleConfigurationRequiresCompleteActiveCredentials() {
        #expect(!TailscaleClient.credentialsAreConfigured(authMethod: .apiKey, apiKey: nil))
        #expect(!TailscaleClient.credentialsAreConfigured(authMethod: .apiKey, apiKey: "  "))
        #expect(TailscaleClient.credentialsAreConfigured(authMethod: .apiKey, apiKey: "tskey-api"))
        #expect(!TailscaleClient.credentialsAreConfigured(
            authMethod: .oauthClient,
            oauthClientID: "client",
            oauthClientSecret: " "
        ))
        #expect(TailscaleClient.credentialsAreConfigured(
            authMethod: .oauthClient,
            oauthClientID: "client",
            oauthClientSecret: "secret"
        ))
    }

    @Test func tailscaleCredentialPresenceDistinguishesAbsentAndUnavailableStores() {
        let suiteName = "sh.glas.test.tailscale-credential-presence.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(TailscaleAuthMethod.apiKey.rawValue, forKey: UserDefaultsKeys.tailscaleAuthMethod)

        #expect(TailscaleClient.credentialPresence(
            defaults: defaults,
            apiKeyProvider: { "tskey-api" },
            oauthCredentialsProvider: { ("", "") }
        ) == .configured)
        #expect(TailscaleClient.credentialPresence(
            defaults: defaults,
            apiKeyProvider: { throw SecretStoreError.notFound },
            oauthCredentialsProvider: { ("", "") }
        ) == .absent)
        #expect(TailscaleClient.credentialPresence(
            defaults: defaults,
            apiKeyProvider: { throw SecretStoreError.encodingFailed },
            oauthCredentialsProvider: { ("", "") }
        ) == .unavailable)

        defaults.set(TailscaleAuthMethod.oauthClient.rawValue, forKey: UserDefaultsKeys.tailscaleAuthMethod)
        #expect(TailscaleClient.credentialPresence(
            defaults: defaults,
            apiKeyProvider: { "" },
            oauthCredentialsProvider: { ("client", "secret") }
        ) == .configured)
        #expect(TailscaleClient.credentialPresence(
            defaults: defaults,
            apiKeyProvider: { "" },
            oauthCredentialsProvider: { throw SecretStoreError.notFound }
        ) == .absent)
        #expect(TailscaleClient.credentialPresence(
            defaults: defaults,
            apiKeyProvider: { "" },
            oauthCredentialsProvider: { throw SecretStoreError.queryFailed(status: -1) }
        ) == .unavailable)
    }

    @Test func tailscaleBoundedTransportRejectsDeclaredAndStreamedOverflow() async throws {
        let limit = 8
        let accepted = try await TailscaleClient.boundedData(
            from: TestByteSequence(count: limit),
            expectedContentLength: Int64(limit),
            maximumBytes: limit
        )
        #expect(accepted.count == limit)

        await #expect(throws: TailscaleError.self) {
            try await TailscaleClient.boundedData(
                from: TestByteSequence(count: 0),
                expectedContentLength: Int64(limit + 1),
                maximumBytes: limit
            )
        }
        await #expect(throws: TailscaleError.self) {
            try await TailscaleClient.boundedData(
                from: TestByteSequence(count: limit + 1),
                expectedContentLength: -1,
                maximumBytes: limit
            )
        }
    }

    @Test func tailscaleOAuthExchangeBoundsBodyTokenAndLifetime() async throws {
        let responseLimit = TailscaleClient.maximumOAuthResponseBytes
        let accepted = try await TailscaleClient.boundedData(
            from: TestByteSequence(count: responseLimit),
            expectedContentLength: Int64(responseLimit),
            maximumBytes: responseLimit
        )
        #expect(accepted.count == responseLimit)
        await #expect(throws: TailscaleError.self) {
            try await TailscaleClient.boundedData(
                from: TestByteSequence(count: 0),
                expectedContentLength: Int64(responseLimit + 1),
                maximumBytes: responseLimit
            )
        }

        #expect(TailscaleClient.oauthExchangeFieldsAreValid(
            accessToken: "token",
            expiresIn: 3_600
        ))
        #expect(!TailscaleClient.oauthExchangeFieldsAreValid(
            accessToken: String(repeating: "a", count: TailscaleClient.maximumOAuthAccessTokenBytes + 1),
            expiresIn: 3_600
        ))
        #expect(!TailscaleClient.oauthExchangeFieldsAreValid(
            accessToken: "token\nleak",
            expiresIn: 3_600
        ))
        #expect(!TailscaleClient.oauthExchangeFieldsAreValid(
            accessToken: "token",
            expiresIn: .infinity
        ))
        #expect(!TailscaleClient.oauthExchangeFieldsAreValid(
            accessToken: "token",
            expiresIn: TailscaleClient.maximumOAuthTokenLifetime + 1
        ))
    }

    @Test func tailscaleDeviceValidatesInventoryAndNormalizesTags() throws {
        let device = try #require(TailscaleDevice(
            id: "device-123",
            hostname: "build-host",
            displayName: "build-host.example.ts.net",
            addresses: ["fd7a:115c:a1e0::1", "100.064.001.009/32"],
            os: "linux",
            lastSeen: nil,
            user: "operator",
            rawTags: ["tag:Production", " production ", "tag:WEB"]
        ))

        #expect(device.ipAddress == "100.64.1.9")
        #expect(device.tags == ["production", "web"])
        #expect(TailscaleDevice.normalizedIPv4Address(from: "100.64.0.1/24") == nil)
        #expect(TailscaleDevice.normalizedIPv4Address(from: "100.64.0.999") == nil)
        #expect(TailscaleDevice(
            id: "device-123",
            hostname: "bad\nhost",
            displayName: "bad.example.ts.net",
            addresses: ["100.64.0.1"],
            os: "linux",
            lastSeen: nil,
            user: "operator",
            rawTags: []
        ) == nil)
        #expect(TailscaleDevice(
            id: "device-123",
            hostname: "build-host",
            displayName: "build-host.example.ts.net",
            addresses: Array(
                repeating: "100.64.0.1",
                count: TailscaleDevice.maximumAddressCount + 1
            ),
            os: "linux",
            lastSeen: nil,
            user: "operator",
            rawTags: []
        ) == nil)
        #expect(TailscaleDevice(
            id: "device-123",
            hostname: "build-host",
            displayName: "build-host.example.ts.net",
            addresses: ["100.64.0.1"],
            os: "linux",
            lastSeen: nil,
            user: "operator",
            rawTags: Array(
                repeating: "tag:production",
                count: TailscaleDevice.maximumTagCount + 1
            )
        ) == nil)
    }

    @Test @MainActor func tailscaleImportDraftPreservesProvenanceWithoutGuessingSSHCredentials() throws {
        let device = try #require(TailscaleDevice(
            id: "device-123",
            hostname: "build-host",
            displayName: "build-host.example.ts.net",
            addresses: ["100.64.1.9"],
            os: "linux",
            lastSeen: nil,
            user: "tailscale-owner",
            rawTags: ["tag:production", "tag:tailscale"]
        ))

        let draft = try #require(TerminalTailscaleImport.draft(for: device))

        #expect(draft.name == "build-host")
        #expect(draft.host == "100.64.1.9")
        #expect(draft.port == 22)
        #expect(draft.username.isEmpty)
        #expect(draft.tags == ["tailscale", "production"])
        #expect(draft.provenance == ServerConnectionProvenance(
            provider: .tailscale,
            externalID: "device-123"
        ))
    }

    @Test func tailscaleInventoryLimitsAcceptBoundaryAndRejectLargerPayloads() {
        #expect(TailscaleClient.inventoryResponseByteCountIsAllowed(
            TailscaleClient.maximumInventoryResponseBytes
        ))
        #expect(!TailscaleClient.inventoryResponseByteCountIsAllowed(
            TailscaleClient.maximumInventoryResponseBytes + 1
        ))
        #expect(TailscaleClient.inventoryDeviceCountIsAllowed(
            TailscaleClient.maximumInventoryDeviceCount
        ))
        #expect(!TailscaleClient.inventoryDeviceCountIsAllowed(
            TailscaleClient.maximumInventoryDeviceCount + 1
        ))
    }

    @Test func serverConnectionProvenanceIsBoundedAndRoundTrips() throws {
        let provenance = try #require(ServerConnectionProvenance(
            provider: .tailscale,
            externalID: "device-123"
        ))
        let server = ServerConfiguration(
            name: "Build Host",
            host: "100.64.1.9",
            username: "operator",
            tags: ["tailscale", "production"],
            provenance: provenance
        )

        let decoded = try JSONDecoder().decode(
            ServerConfiguration.self,
            from: JSONEncoder().encode(server)
        )
        #expect(decoded.provenance == provenance)

        let legacyServer = ServerConfiguration(
            name: "Legacy Host",
            host: "legacy.example.com",
            username: "operator"
        )
        let decodedLegacyServer = try JSONDecoder().decode(
            ServerConfiguration.self,
            from: JSONEncoder().encode(legacyServer)
        )
        #expect(decodedLegacyServer.provenance == nil)
        #expect(ServerConnectionProvenance(
            provider: .tailscale,
            externalID: String(repeating: "x", count: 257)
        ) == nil)
        #expect(ServerConnectionProvenance(
            provider: .tailscale,
            externalID: "device\n123"
        ) == nil)
    }

    @Test @MainActor func tailscaleCredentialInvalidationClearsInventoryState() throws {
        let device = try #require(TailscaleDevice(
            id: "device-123",
            hostname: "build-host",
            displayName: "build-host.example.ts.net",
            addresses: ["100.64.1.9"],
            os: "linux",
            lastSeen: nil,
            user: "operator",
            rawTags: ["tag:production"]
        ))
        let client = TailscaleClient()
        client.devices = [device]
        client.errorMessage = "old account"

        client.invalidateCredentialState()

        #expect(client.devices.isEmpty)
        #expect(client.errorMessage == nil)
        #expect(client.isLoading == false)
    }

    // MARK: - SettingsManager Tests

    @Test @MainActor func settingsManagerDefaults() {
        let settings = SettingsManager(loadImmediately: false)

        #expect(settings.autoReconnect == true)
        #expect(settings.confirmBeforeClosing == true)
        #expect(settings.saveScrollback == true)
        #expect(settings.maxScrollbackLines == 10000)
        #expect(settings.bellEnabled == false)
        #expect(settings.visualBell == true)
        #expect(settings.cursorStyle == "Block")
        #expect(settings.blinkingCursor == true)
        // A view over the shell's layer state, so it tracks the default rather than a literal.
        #expect(settings.glassFrost == GlassLayerState.default.material.rawValue)
        #expect(settings.backgroundFill == 0.0)
        #expect(settings.interactiveGlass == true)
        #expect(settings.glassTint == "None")
    }

    @Test @MainActor func settingsManagerSnippetCRUD() {
        let settings = SettingsManager(loadImmediately: false)

        let snippet = CommandSnippet(
            name: "List files",
            command: "ls -la",
            description: "List all files",
            tags: ["filesystem"]
        )
        settings.addSnippet(snippet)
        #expect(settings.snippets.count == 1)
        #expect(settings.snippets.first?.name == "List files")

        var modified = snippet
        modified.name = "List all"
        settings.updateSnippet(modified)
        #expect(settings.snippets.first?.name == "List all")

        settings.useSnippet(snippet.id)
        #expect(settings.snippets.first?.useCount == 1)

        settings.deleteSnippet(snippet)
        #expect(settings.snippets.isEmpty)
    }

    /// W20: the override is a window's look now, kept by its workgroup off the Mac.
    @Test @MainActor func workgroupKeepsItsWindowLook() {
        let manager = SessionManager(loadImmediately: false)
        let workgroupID = manager.createWorkgroup(name: "alpha", colorTag: .blue)

        #expect(manager.workgroup(for: workgroupID)?.windowSettings.isEmpty == true)

        var look = TerminalSessionOverride()
        look.backgroundFill = 0.8
        look.interactiveGlass = false
        manager.setWindowSettings(look.windowSettings, forWorkgroup: workgroupID)

        let result = manager.workgroup(for: workgroupID)?.windowSettings
        #expect(result?[GlassLayerSettings.opacity] == 0.8)
        #expect(result?[TerminalWindowSettings.interactiveGlass] == false)
    }

    // MARK: - Layout Persistence Tests

    @Test func legacyLayoutServerIDsMigrateToVersionedSessionIntentions() throws {
        let layoutID = UUID()
        let firstServerID = UUID()
        let secondServerID = UUID()
        let legacyRecord: [String: Any] = [
            "id": layoutID.uuidString,
            "name": "Legacy Layout",
            "serverIDs": [firstServerID.uuidString, secondServerID.uuidString],
            "createdAt": 123.0
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyRecord)

        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: legacyData)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.needsMigration)
        #expect(decoded.serverIDs == [firstServerID, secondServerID])
        #expect(decoded.sessionIntents.allSatisfy { $0.isSupported })

        let migrated = decoded.migratedToCurrentSchema()
        let canonicalData = try JSONEncoder().encode(migrated)
        let canonicalObject = try #require(
            JSONSerialization.jsonObject(with: canonicalData) as? [String: Any]
        )

        #expect(migrated.schemaVersion == LayoutPreset.currentSchemaVersion)
        #expect(!migrated.needsMigration)
        #expect(canonicalObject["sessionIntents"] != nil)
        #expect(canonicalObject["serverIDs"] == nil)
    }

    @Test func layoutRestorationPreservesDuplicateSessionIntentions() throws {
        let server = ServerConfiguration(
            name: "Shared Endpoint",
            host: "example.com",
            port: 22,
            username: "user"
        )
        let preset = LayoutPreset(name: "Two Terminals", serverIDs: [server.id, server.id])
        let roundTripped = try JSONDecoder().decode(
            LayoutPreset.self,
            from: JSONEncoder().encode(preset)
        )

        let plan = LayoutRestorationPlan(preset: roundTripped, availableServers: [server])

        #expect(roundTripped.serverIDs == [server.id, server.id])
        #expect(plan.targets.count == 2)
        #expect(plan.targets.allSatisfy { $0.server?.id == server.id })
        #expect(plan.failures.isEmpty)
    }

    @Test func layoutRestorationAggregatesMissingServersWithoutDiscardingValidSessions() {
        let availableServer = ServerConfiguration(
            name: "Available",
            host: "available.example.com",
            port: 22,
            username: "user"
        )
        let missingServerID = UUID()
        let preset = LayoutPreset(
            name: "Partial Layout",
            serverIDs: [missingServerID, availableServer.id]
        )

        let plan = LayoutRestorationPlan(preset: preset, availableServers: [availableServer])

        #expect(plan.targets.count == 1)
        #expect(plan.targets.first?.server?.id == availableServer.id)
        #expect(plan.failures.count == 1)
        #expect(plan.failures.first?.contains("Session 1") == true)
        #expect(plan.failures.first?.contains("no longer exists") == true)
    }

    @Test func workgroupRoundTripsColorLocalAndSSHCommandRecipes() throws {
        let serverID = UUID()
        let preset = LayoutPreset(
            name: "  Production  ",
            colorTag: .purple,
            sessionIntents: [
                .init(kind: .local, label: "Editor", startupCommand: "cd ~/src && nvim"),
                .init(serverID: serverID, label: "Logs", startupCommand: "journalctl -f"),
            ]
        )

        let decoded = try JSONDecoder().decode(
            LayoutPreset.self,
            from: JSONEncoder().encode(preset)
        )

        #expect(decoded.name == "Production")
        #expect(decoded.colorTag == .purple)
        #expect(decoded.sessionIntents.map(\.kind) == [.local, .ssh])
        #expect(decoded.sessionIntents.map(\.startupCommand) == [
            "cd ~/src && nvim",
            "journalctl -f",
        ])
        #expect(decoded.isValidForPersistence)
    }

    @Test func workgroupMigratesVersionTwoSSHIntentWithSafeDefaults() throws {
        let layoutID = UUID()
        let serverID = UUID()
        let record: [String: Any] = [
            "id": layoutID.uuidString,
            "name": "Old Layout",
            "schemaVersion": 2,
            "sessionIntents": [[
                "schemaVersion": 1,
                "serverID": serverID.uuidString,
                "restoration": "freshAuthorizedSession",
            ]],
            "createdAt": 123.0,
        ]
        let decoded = try JSONDecoder().decode(
            LayoutPreset.self,
            from: JSONSerialization.data(withJSONObject: record)
        )

        #expect(decoded.needsMigration)
        let migrated = decoded.migratedToCurrentSchema()
        #expect(migrated.colorTag == .blue)
        #expect(migrated.sessionIntents.first?.kind == .ssh)
        #expect(migrated.sessionIntents.first?.serverID == serverID)
        #expect(migrated.sessionIntents.first?.startupCommand == nil)
        #expect(migrated.isValidForPersistence)
    }

    @Test func workgroupRejectsUnsafeOrMultilineStartupCommands() {
        #expect(TerminalStartupCommandTicket(command: "") == nil)
        #expect(TerminalStartupCommandTicket(command: "first\nsecond") == nil)
        #expect(TerminalStartupCommandTicket(command: "bad\0command") == nil)
        #expect(TerminalStartupCommandTicket(command: String(
            repeating: "x",
            count: TerminalStartupCommandTicket.maximumCommandBytes + 1
        )) == nil)
    }

    // MARK: - Error Classification Tests

    @Test @MainActor func userFacingMessageForPasswordRequired() {
        let server = ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        )
        let message = SSHConnection.userFacingMessage(for: SSHError.passwordRequired, server: server)
        #expect(message.contains("password"))
        #expect(message.contains("user@example.com:22"))
    }

    @Test @MainActor func userFacingMessageForConnectionFailed() {
        let server = ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        )
        let message = SSHConnection.userFacingMessage(for: SSHError.connectionFailed, server: server)
        #expect(message.contains("example.com:22"))
    }

    @Test @MainActor func userFacingMessageForInvalidHost() {
        let server = ServerConfiguration(
            name: "Test",
            host: "bad://host",
            port: 22,
            username: "user"
        )
        let message = SSHConnection.userFacingMessage(for: SSHError.invalidHost("bad://host"), server: server)
        #expect(message.contains("bad://host"))
        #expect(message.contains("not valid"))
    }

    @Test @MainActor func userFacingMessageForUnsupportedAuthMethod() {
        let server = ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        )
        let message = SSHConnection.userFacingMessage(
            for: SSHError.unsupportedAuthMethod("SSH Agent authentication is unavailable in this release."),
            server: server
        )
        #expect(message == "SSH Agent authentication is unavailable in this release.")
    }

    @Test @MainActor func userFacingMessageForInvalidPort() {
        let server = ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 70_000,
            username: "user"
        )

        let message = SSHConnection.userFacingMessage(for: SSHError.invalidPort(server.port), server: server)

        #expect(message.contains("70000"))
        #expect(message.contains("1 through 65535"))
    }


    @Test func legacyAlgorithmsAreDisabledForExistingServerRecords() throws {
        var server = ServerConfiguration(
            name: "Legacy",
            host: "legacy.example.com",
            port: 22,
            username: "user"
        )
        server.allowLegacyAlgorithms = nil

        let encoded = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(ServerConfiguration.self, from: encoded)

        #expect(decoded.allowLegacyAlgorithms == nil)
        #expect(decoded.legacyAlgorithmsEnabled == false)
        #expect(decoded.initialTerminalColumns == nil)
        #expect(decoded.initialTerminalRows == nil)
    }

    @Test func perConnectionTerminalGeometryRoundTripsWithServerRecord() throws {
        let server = ServerConfiguration(
            name: "Sized",
            host: "sized.example.com",
            username: "user",
            initialTerminalColumns: 146,
            initialTerminalRows: 44
        )

        let decoded = try JSONDecoder().decode(
            ServerConfiguration.self,
            from: JSONEncoder().encode(server)
        )

        #expect(decoded.initialTerminalColumns == 146)
        #expect(decoded.initialTerminalRows == 44)
    }

    @Test @MainActor func channelClosedErrorDetection() {
        #expect(SSHConnection.isChannelClosedError(ChannelError.eof))
        #expect(SSHConnection.isChannelClosedError(ChannelError.alreadyClosed))
        #expect(SSHConnection.isChannelClosedError(ChannelError.inputClosed))
        #expect(SSHConnection.isChannelClosedError(ChannelError.outputClosed))
        #expect(!SSHConnection.isChannelClosedError(ChannelError.connectPending))
        #expect(!SSHConnection.isChannelClosedError(SSHError.connectionFailed))
    }

    @Test func generatedCommandPolicyAllowsOnlyClassifiedReadOnlyCommands() {
        #expect(GeneratedCommandPolicy.assess("ls -la").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("git status").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("rm -rf build").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("cat script | sh").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("sudo ls").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("curl https://example.com").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("git reset --hard").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("find . -delete").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("ls\nrm file").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("find . -fprint /tmp/glas-proof").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("find . -fls /tmp/glas-proof").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("less -o /tmp/copied-secret /etc/passwd").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("rg --pre touch pattern .").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("hostname attacker-controlled-name").requiresConfirmation)
        #expect(GeneratedCommandPolicy.assess("date -s @0").requiresConfirmation)
    }

    @Test func generatedCommandPolicyRejectsControlAndUnicodeFormatSpoofing() {
        #expect(GeneratedCommandPolicy.assess("ls -la").isExecutable)

        let visuallySpoofedCommands = [
            "ls\u{0000}-la",
            "echo safe\u{202E}txt",
            "git \u{2066}status\u{2069}",
            "rm\u{200B} -rf build",
        ]
        for command in visuallySpoofedCommands {
            let assessment = GeneratedCommandPolicy.assess(command)
            #expect(!assessment.isExecutable)
            #expect(assessment.reasons.contains {
                $0.contains("control or invisible Unicode formatting")
            })
        }
    }

    @Test func aiResponseParserExtractsRequiredLabeledSections() throws {
        let suggestion = try #require(AIResponseParser.commandSuggestion(from: """
        COMMAND: ls -la
        EXPLANATION: Lists all files, including hidden files.
        RISK: safe
        """))
        #expect(suggestion.command == "ls -la")
        #expect(suggestion.explanation == "Lists all files, including hidden files.")
        #expect(suggestion.riskLevel == "safe")

        let explanation = try #require(AIResponseParser.errorExplanation(from: """
        PROBLEM: The directory does not exist.
        FIX:
        REASONING: No automatic fix is safe without the intended path.
        """))
        #expect(explanation.problem == "The directory does not exist.")
        #expect(explanation.suggestedFix.isEmpty)
        #expect(explanation.reasoning == "No automatic fix is safe without the intended path.")
    }

    @Test func aiResponseParserRejectsMissingSections() {
        #expect(AIResponseParser.commandSuggestion(from: "COMMAND: ls") == nil)
        #expect(AIResponseParser.errorExplanation(
            from: "PROBLEM: failed\nREASONING: unknown"
        ) == nil)
        #expect(AIResponseParser.commandSuggestion(from: """
        COMMAND: ls
        EXPLANATION: first
        EXPLANATION: duplicate
        RISK: safe
        """) == nil)
        #expect(AIResponseParser.commandSuggestion(from: """
        COMMAND: ls
        EXPLANATION: lists files
        RISK: unknown
        """) == nil)
        #expect(AIResponseParser.commandSuggestion(from: """
        COMMAND: ```sh
        ls
        ```
        EXPLANATION: lists files
        RISK: safe
        """) == nil)
    }

    @Test func aiResponseParserNormalizesLegacyCarriageReturns() throws {
        let suggestion = try #require(AIResponseParser.commandSuggestion(
            from: "COMMAND: pwd\rEXPLANATION: Prints the current directory.\rRISK: SAFE"
        ))
        #expect(suggestion.command == "pwd")
        #expect(suggestion.riskLevel == "safe")
    }

    @Test func sftpBasenamePolicyRejectsTraversalAndSeparators() {
        #expect(SFTPBrowserView.isSafeBasename("report.txt"))
        #expect(SFTPBrowserView.isSafeBasename("résumé.txt"))
        #expect(!SFTPBrowserView.isSafeBasename(""))
        #expect(!SFTPBrowserView.isSafeBasename("."))
        #expect(!SFTPBrowserView.isSafeBasename(".."))
        #expect(!SFTPBrowserView.isSafeBasename("../secret"))
        #expect(!SFTPBrowserView.isSafeBasename("folder/file"))
        #expect(!SFTPBrowserView.isSafeBasename("folder\\file"))
        #expect(!SFTPBrowserView.isSafeBasename("/absolute"))
        #expect(!SFTPBrowserView.isSafeBasename(" trailing "))
        #expect(!SFTPBrowserView.isSafeBasename("nul\0byte"))
        #expect(!SFTPBrowserView.isSafeBasename("line\nbreak.txt"))
        #expect(!SFTPBrowserView.isSafeBasename("report\u{202E}txt.exe"))
        #expect(!SFTPBrowserView.isSafeBasename("zero\u{200B}width.txt"))
        #expect(!SFTPBrowserView.isSafeBasename("re\u{301}sume\u{301}.txt"))
        #expect(SFTPBrowserView.isSafeBasename("r\u{00E9}sum\u{00E9}.txt"))
    }

    @Test func sftpClipboardURLContainsOnlyRemoteReferenceMetadata() throws {
        let url = try #require(SFTPBrowserView.remoteClipboardURL(
            username: "casey",
            host: "example.com",
            port: 22,
            path: "/var/www/My File#1.txt"
        ))

        #expect(url.absoluteString == "sftp://casey@example.com:22/var/www/My%20File%231.txt")
        #expect(url.password == nil)
    }

    @Test func sftpRemotePathPolicyRejectsSelfAndDescendantDestinations() {
        #expect(SFTPBrowserView.remotePath(directory: "/var/www", basename: "app") == "/var/www/app")
        #expect(SFTPBrowserView.remotePath(directory: "/", basename: "app") == "/app")
        #expect(SFTPBrowserView.remoteParentPath("/var/www/app") == "/var/www")
        #expect(SFTPBrowserView.remoteParentPath("/app") == "/")
        #expect(SFTPBrowserView.isRemotePath("/var/www/app", inside: "/var/www/app"))
        #expect(SFTPBrowserView.isRemotePath("/var/www/app/cache", inside: "/var/www/app"))
        #expect(!SFTPBrowserView.isRemotePath("/var/www/application", inside: "/var/www/app"))
        #expect(!SFTPBrowserView.isRemotePath("/var/backups", inside: "/var/www/app"))
    }

    @Test func sftpRemoteShellArgumentsUsePOSIXSingleQuoteEscaping() {
        let quoted = SFTPBrowserView.shellQuote("/var/www/it's safe; touch /tmp/nope")
        #expect(quoted == "'/var/www/it'\"'\"'s safe; touch /tmp/nope'")

        let command = SFTPBrowserView.remoteCopyCommand(
            sourcePath: "/var/www/it's safe; touch /tmp/nope",
            stagingPath: "/backup/.glas-sh-copy-test.partial"
        )
        #expect(command.contains("command cp -Rp '/var/www/it'\"'\"'s safe; touch /tmp/nope' '/backup/.glas-sh-copy-test.partial'"))
        #expect(!command.contains("command cp -Rp /var/www/it's safe"))
    }

    @Test func sftpRemotePermissionFailuresDescribePhasePathAndOutcome() {
        let readFailure = SFTPRemoteOperationPhase.readSource.failureMessage(
            path: "/srv/private/report.txt",
            serverDescription: "Permission denied"
        )
        #expect(readFailure.contains("read permission"))
        #expect(readFailure.contains("/srv/private/report.txt"))
        #expect(readFailure.contains("No destination was published"))

        let publishFailure = SFTPRemoteOperationPhase.publishDestination.failureMessage(
            path: "/srv/archive/report.txt",
            serverDescription: "Operation not permitted"
        )
        #expect(publishFailure.contains("write and search permission"))
        #expect(publishFailure.contains("No existing destination was overwritten"))
        #expect(publishFailure.contains("hidden staging item may remain"))

        let cleanupFailure = SFTPRemoteOperationPhase.removeRetiredSource.failureMessage(
            path: "/srv/private/.glas-sh-move-test.retained",
            serverDescription: "Permission denied"
        )
        #expect(cleanupFailure.contains("verified destination was created"))
        #expect(cleanupFailure.contains("Both the destination and retained source remain"))

        let retainedVerificationFailure = SFTPRemoteOperationPhase.verifyRetiredSource.failureMessage(
            path: "/srv/private/.glas-sh-move-test.retained",
            serverDescription: "The retained item changed before cleanup."
        )
        #expect(retainedVerificationFailure.contains("verified destination was created"))
        #expect(retainedVerificationFailure.contains("was not deleted"))
        #expect(retainedVerificationFailure.contains("manual recovery"))
    }

    @Test func sftpRetainedRemoteSourceMustMatchCopiedBaselineBeforeDeletion() {
        let copied = [SFTPRemoteManifestEntry(
            relativePath: "",
            kind: .file,
            size: 6,
            permissions: 0o644,
            accessTime: nil,
            modificationTime: Date(timeIntervalSince1970: 1_700_000_000),
            digest: Data("copied".utf8)
        )]
        let identicalRetainedSource = copied
        let replacedRetainedSource = [SFTPRemoteManifestEntry(
            relativePath: "",
            kind: .file,
            size: 11,
            permissions: 0o644,
            accessTime: nil,
            modificationTime: Date(timeIntervalSince1970: 1_700_000_001),
            digest: Data("replacement".utf8)
        )]

        #expect(SFTPBrowserView.retainedSourceCanBeRemoved(
            copiedBaseline: copied,
            retainedSource: identicalRetainedSource
        ))
        #expect(!SFTPBrowserView.retainedSourceCanBeRemoved(
            copiedBaseline: copied,
            retainedSource: replacedRetainedSource
        ))
    }

    @Test @MainActor func sftpTransferActivityReportsHonestLifecycleAndSummary() throws {
        let store = SFTPTransferActivityStore(maximumTerminalItemCount: 20)
        let downloadID = store.enqueue(
            kind: .download,
            filename: "archive.iso",
            totalBytes: 100
        )
        _ = store.enqueue(kind: .upload, filename: "notes.txt")

        #expect(store.headline == "2 transfers waiting")
        #expect(store.pendingCount == 2)

        store.begin(downloadID)
        store.apply(
            .transferring(completedBytes: 25, totalBytes: 100),
            to: downloadID
        )
        #expect(store.headline == "Downloading archive.iso")
        #expect(try #require(store.activity(downloadID)).progress == 0.25)
        #expect(try #require(store.activity(downloadID)).statusLabel == "25%")

        store.apply(.verifying, to: downloadID)
        #expect(try #require(store.activity(downloadID)).statusLabel == "Verifying")

        store.complete(downloadID)
        #expect(try #require(store.activity(downloadID)).state == .completed)
        #expect(try #require(store.activity(downloadID)).completedBytes == 100)
        #expect(store.headline == "1 transfer waiting")
    }

    @Test @MainActor func sftpTransferActivityBoundsHistoryWithoutDroppingWork() {
        let store = SFTPTransferActivityStore(maximumTerminalItemCount: 2)
        let activeID = store.enqueue(kind: .finderDownload, filename: "active.bin")
        store.begin(activeID)
        let pendingID = store.enqueue(kind: .upload, filename: "pending.bin")

        var terminalIDs: [UUID] = []
        for index in 1...3 {
            let id = store.enqueue(kind: .download, filename: "done-\(index).bin")
            terminalIDs.append(id)
            store.begin(id)
            store.complete(id)
        }

        #expect(store.activity(activeID)?.state == .transferring)
        #expect(store.activity(pendingID)?.state == .pending)
        #expect(store.activity(terminalIDs[0]) == nil)
        #expect(store.displayedActivities.map(\.id) == [
            activeID,
            pendingID,
            terminalIDs[2],
            terminalIDs[1],
        ])

        store.clearTerminalActivities()
        #expect(store.activities.map(\.id) == [activeID, pendingID])

        store.cancelPending([pendingID], detail: "Batch cancelled.")
        store.fail(activeID, detail: "Connection lost.")
        #expect(store.activity(pendingID)?.state == .cancelled)
        #expect(store.activity(activeID)?.state == .failed)
        #expect(store.headline == "1 transfer failed")
    }



    #if os(macOS)

    @Test func sftpFilePromiseForwardsFinderDestinationWithoutBlocking() async throws {
        let destination = URL(fileURLWithPath: "/tmp/glas-sh-promised-file.txt")
        let (receivedDestinations, signalDestination) = AsyncStream<URL>.makeStream()
        let (lifecycleEvents, signalLifecycleEvent) = AsyncStream<String>.makeStream()
        let payload = SFTPFilePromisePayload(
            id: "promise-test",
            filename: "promised-file.txt",
            fileType: .data,
            prepare: {
                signalLifecycleEvent.yield("pending")
            }
        ) { receivedDestination in
            signalLifecycleEvent.yield("active")
            signalLifecycleEvent.finish()
            signalDestination.yield(receivedDestination)
            signalDestination.finish()
        }

        try await payload.fulfill(at: destination)

        var receivedIterator = receivedDestinations.makeAsyncIterator()
        #expect(await receivedIterator.next() == destination)
        var lifecycleIterator = lifecycleEvents.makeAsyncIterator()
        #expect(await lifecycleIterator.next() == "pending")
        #expect(await lifecycleIterator.next() == "active")
    }

    @Test func sftpFilePromiseRegistryCancelsActiveAndRejectsLateTransfers() async {
        let registry = SFTPFilePromiseTransferRegistry()
        let (started, signalStarted) = AsyncStream<Void>.makeStream()
        let transfer = Task {
            try await registry.perform {
                signalStarted.yield()
                try await Task.sleep(for: .seconds(30))
            }
        }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()

        await registry.cancelAllAndWait()

        do {
            try await transfer.value
            Issue.record("Expected active file-promise transfer to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
        await #expect(throws: CancellationError.self) {
            try await registry.perform {}
        }
    }
    #endif

    @Test func sftpDownloadReadWindowIsContiguousAndBoundedToTwoMiB() {
        let chunkSize = SFTPBrowserView.downloadReadChunkSize
        let window = SFTPBrowserView.downloadReadWindow(
            from: 4_096,
            through: 4_096 + UInt64(chunkSize) * 12
        )

        #expect(window.count == SFTPBrowserView.downloadMaximumConcurrentReads)
        #expect(window.first?.offset == 4_096)
        #expect(
            window.reduce(0) { $0 + Int($1.length) }
                == 2 * 1024 * 1024
        )
        for index in window.indices.dropFirst() {
            let previous = window[index - 1]
            #expect(window[index].offset == previous.offset + UInt64(previous.length))
        }

        let tail = SFTPBrowserView.downloadReadWindow(
            from: 0,
            through: UInt64(chunkSize) * 2 + 17
        )
        #expect(tail.map(\.length) == [chunkSize, chunkSize, 17])
    }

    @Test func sftpDownloadReadBatchStopsAtShortReadAndAdaptsNextWindow() throws {
        let requests = SFTPBrowserView.downloadReadWindow(
            from: 0,
            through: UInt64(SFTPBrowserView.downloadReadChunkSize) * 3
        )
        let shortReadSize = 32 * 1024
        let decision = try SFTPBrowserView.downloadReadBatchDecision(
            requests: requests,
            readableByteCounts: [
                Int(requests[0].length),
                shortReadSize,
                Int(requests[2].length),
            ]
        )

        #expect(decision.acceptedResponseCount == 2)
        #expect(decision.nextChunkSize == UInt32(shortReadSize))
        #expect(!decision.reachedEOF)

        let acceptedBytes = UInt64(requests[0].length) + UInt64(shortReadSize)
        let nextWindow = SFTPBrowserView.downloadReadWindow(
            from: acceptedBytes,
            through: acceptedBytes + UInt64(shortReadSize) * 3,
            chunkSize: try #require(decision.nextChunkSize)
        )
        #expect(nextWindow.first?.offset == acceptedBytes)
        #expect(nextWindow.allSatisfy { $0.length == UInt32(shortReadSize) })
    }


    @Test func sftpRemoteEditorUsesOneEightMiBCeiling() {
        #expect(
            SFTPBrowserView.remoteEditorConfiguration.largeFileByteCeiling
                == 8 * 1024 * 1024
        )
    }


    @Test func sftpContainmentRejectsParentTraversal() {
        let folder = URL(fileURLWithPath: "/tmp/glas-sftp-destination", isDirectory: true)

        #expect(SFTPBrowserView.isContained(folder.appendingPathComponent("safe.txt"), in: folder))
        #expect(!SFTPBrowserView.isContained(folder.appendingPathComponent("../escape.txt"), in: folder))
    }

    @Test func sftpLocalFileOpenRejectsSymbolicLinks() throws {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("glas-sftp-no-follow-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: folder) }

        let source = folder.appendingPathComponent("source.txt")
        let link = folder.appendingPathComponent("partial-link")
        try Data("trusted".utf8).write(to: source)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: source)

        #expect(throws: (any Error).self) {
            try SFTPBrowserView.localFileIdentityNoFollow(at: link)
        }
        #expect(try SFTPBrowserView.localFileIdentityNoFollow(at: source).size == 7)
    }

    @Test func sftpRetainedDestinationDirectoryPreventsParentSwapRedirection() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("glas-sftp-directory-fd-\(UUID().uuidString)", isDirectory: true)
        let selectedPath = root.appendingPathComponent("selected", isDirectory: true)
        let retainedPath = root.appendingPathComponent("retained", isDirectory: true)
        let victim = root.appendingPathComponent("victim.txt")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: selectedPath, withIntermediateDirectories: false)
        try Data("untouched".utf8).write(to: victim)
        defer { try? fileManager.removeItem(at: root) }

        let openedDirectory = try SFTPBrowserView.openLocalDirectoryNoFollow(at: selectedPath)
        defer { try? openedDirectory.directory.close() }

        // Replace the selected pathname after acquisition. Every transfer operation
        // must remain anchored to the directory inode the user actually selected.
        try fileManager.moveItem(at: selectedPath, to: retainedPath)
        try fileManager.createDirectory(at: selectedPath, withIntermediateDirectories: false)
        let replacementPartial = selectedPath.appendingPathComponent("partial")
        try fileManager.createSymbolicLink(at: replacementPartial, withDestinationURL: victim)

        let partial = try SFTPBrowserView.createProtectedTemporaryFile(
            in: openedDirectory.directory,
            name: "partial"
        )
        try partial.file.write(contentsOf: Data("download".utf8))
        try partial.file.synchronize()
        let completedIdentity = try SFTPBrowserView.localFileIdentity(for: partial.file)
        try SFTPBrowserView.moveLocalFileNoClobber(
            in: openedDirectory.directory,
            sourceName: "partial",
            destinationName: "report.txt",
            matching: completedIdentity
        )
        try partial.file.seek(toOffset: 0)
        #expect(try partial.file.readToEnd() == Data("download".utf8))
        #expect(
            try SFTPBrowserView.localFileIdentity(for: partial.file)
                .isSameFile(as: completedIdentity)
        )
        try partial.file.close()
        #expect(try fileManager.destinationOfSymbolicLink(atPath: replacementPartial.path) == victim.path)
        #expect(try Data(contentsOf: victim) == Data("untouched".utf8))
        #expect(
            try SFTPBrowserView.localDirectoryIdentity(for: openedDirectory.directory)
                == openedDirectory.identity
        )

        let cleanup = try SFTPBrowserView.createProtectedTemporaryFile(
            in: openedDirectory.directory,
            name: "cleanup"
        )
        try cleanup.file.close()
        let replacementCleanup = selectedPath.appendingPathComponent("cleanup")
        try fileManager.createSymbolicLink(at: replacementCleanup, withDestinationURL: victim)
        try SFTPBrowserView.removeLocalFileIfMatching(
            in: openedDirectory.directory,
            name: "cleanup",
            identity: cleanup.identity
        )

        #expect(!fileManager.fileExists(atPath: retainedPath.appendingPathComponent("cleanup").path))
        #expect(try fileManager.destinationOfSymbolicLink(atPath: replacementCleanup.path) == victim.path)
        #expect(try Data(contentsOf: victim) == Data("untouched".utf8))
    }

    @Test func sftpRetainedSourceDescriptorDetectsInPlaceMutation() throws {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("glas-sftp-source-identity-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: folder) }

        let source = folder.appendingPathComponent("source.txt")
        try Data("before".utf8).write(to: source)
        let opened = try SFTPBrowserView.openLocalSourceNoFollow(at: source)
        defer { try? opened.file.close() }

        let writer = try FileHandle(forWritingTo: source)
        try writer.seek(toOffset: 0)
        try writer.write(contentsOf: Data("after!".utf8))
        try writer.synchronize()
        try writer.close()

        let changedIdentity = try SFTPBrowserView.localFileIdentity(for: opened.file)
        #expect(changedIdentity.isSameFile(as: opened.identity))
        #expect(changedIdentity != opened.identity)
        #expect(!SFTPBrowserView.localFile(opened.file, matches: opened.identity))
    }

    @Test func sftpCommitGateObservesTaskCancellation() async {
        let task = Task { () -> Bool in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                // Continue to the actual commit gate after cancellation wakes the task.
            }
            do {
                try SFTPBrowserView.checkCancellationBeforeCommit()
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        task.cancel()

        #expect(await task.value)
    }

    @Test func sftpDownloadResumeIdentityBindsRemoteSourceVersion() {
        let serverID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let identity = SFTPBrowserView.downloadResumeIdentity(
            serverID: serverID,
            remotePath: "/exports/report.txt",
            size: 4_096,
            modificationTime: modified
        )

        #expect(identity == SFTPBrowserView.downloadResumeIdentity(
            serverID: serverID,
            remotePath: "/exports/report.txt",
            size: 4_096,
            modificationTime: modified
        ))
        #expect(identity != SFTPBrowserView.downloadResumeIdentity(
            serverID: serverID,
            remotePath: "/exports/report.txt",
            size: 4_097,
            modificationTime: modified
        ))
        #expect(identity != SFTPBrowserView.downloadResumeIdentity(
            serverID: serverID,
            remotePath: "/exports/report.txt",
            size: 4_096,
            modificationTime: modified.addingTimeInterval(1)
        ))
    }

    @Test func sftpUploadResumeIdentityBindsDestinationAndLocalSource() {
        let serverID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let identity = SFTPBrowserView.uploadResumeIdentity(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report.txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_000
        )

        #expect(identity == SFTPBrowserView.uploadResumeIdentity(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report.txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_000
        ))
        #expect(identity != SFTPBrowserView.uploadResumeIdentity(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report (2).txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_000
        ))
        #expect(identity != SFTPBrowserView.uploadResumeIdentity(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report.txt",
            sourceName: "report.txt",
            sourceSize: 8_193,
            sourceModificationTime: 1_700_000_000
        ))
    }

    @Test func sftpDownloadResumeDecisionRejectsUnsafeAndReplacesOversizedCandidates() {
        #expect(SFTPBrowserView.localResumeDecision(
            fileExists: false,
            isRegularAndContained: false,
            size: nil,
            expectedSize: 4_096
        ) == .create)
        #expect(SFTPBrowserView.localResumeDecision(
            fileExists: true,
            isRegularAndContained: true,
            size: 2_048,
            expectedSize: 4_096
        ) == .resume(offset: 2_048))
        #expect(SFTPBrowserView.localResumeDecision(
            fileExists: true,
            isRegularAndContained: true,
            size: 4_097,
            expectedSize: 4_096
        ) == .replaceOversized)
        #expect(SFTPBrowserView.localResumeDecision(
            fileExists: true,
            isRegularAndContained: false,
            size: 2_048,
            expectedSize: 4_096
        ) == .rejectUnsafe)
        #expect(SFTPBrowserView.localResumeDecision(
            fileExists: true,
            isRegularAndContained: true,
            size: 2_048,
            expectedSize: nil
        ) == .rejectUnsafe)
        #expect(SFTPBrowserView.resumeChunksMatch(
            source: Data("verified prefix".utf8),
            retained: Data("verified prefix".utf8)
        ))
        #expect(!SFTPBrowserView.resumeChunksMatch(
            source: Data("verified prefix".utf8),
            retained: Data("corrupt prefix!".utf8)
        ))
        #expect(!SFTPBrowserView.resumeChunksMatch(source: Data(), retained: Data()))
    }

    @Test func sftpUploadResumeRecordRequiresEveryBoundIdentityField() throws {
        let serverID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let record = SFTPUploadResumeRecord(
            version: SFTPUploadResumeRecord.currentVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report.txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_000,
            partialName: ".glas-sh-upload-11111111-2222-3333-4444-555555555555.partial"
        )

        #expect(record.matches(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report.txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_000
        ))
        let decodedRecord = try JSONDecoder().decode(
            SFTPUploadResumeRecord.self,
            from: JSONEncoder().encode(record)
        )
        #expect(decodedRecord.matches(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report.txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_000
        ))
        #expect(!record.matches(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report (2).txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_000
        ))
        #expect(!record.matches(
            serverID: serverID,
            remoteDirectory: "/incoming",
            finalName: "report.txt",
            sourceName: "report.txt",
            sourceSize: 8_192,
            sourceModificationTime: 1_700_000_001
        ))
    }

    @Test func sftpUploadMetadataNeverDropsUnresolvedMappingsAtCapacity() {
        let fullDirectory = Set((0..<128).map { "\($0).json" })

        #expect(!SFTPBrowserView.canReserveUploadMetadataRecord(
            existingRecordNames: fullDirectory,
            requestedName: "new.json",
            maximumCount: 128
        ))
        #expect(SFTPBrowserView.canReserveUploadMetadataRecord(
            existingRecordNames: fullDirectory,
            requestedName: "64.json",
            maximumCount: 128
        ))
        #expect(SFTPBrowserView.canReserveUploadMetadataRecord(
            existingRecordNames: ["existing.json"],
            requestedName: "new.json",
            maximumCount: 128
        ))
    }

    @Test func tailscaleFormEncodingPreventsDelimiterSmuggling() {
        let body = TailscaleClient.formEncodedBody([
            ("client id", "a+b&c=d/secret")
        ])

        #expect(String(decoding: body, as: UTF8.self) == "client+id=a%2Bb%26c%3Dd%2Fsecret")
    }

    @Test func tailscaleOAuthTokenCacheBindsCredentialIdentityExpiryAndClear() {
        let now = Date(timeIntervalSince1970: 1_000)
        let credentialsA = (clientID: "client-a", clientSecret: "secret-a")
        let credentialsB = (clientID: "client-b", clientSecret: "secret-b")
        var cache = TailscaleOAuthTokenCache()

        let storedA = cache.store("token-a", expiresIn: 3_600, for: credentialsA, now: now)
        let cachedA = cache.token(for: credentialsA, now: now.addingTimeInterval(60))
        let rotatedCredentialMiss = cache.token(for: credentialsB, now: now.addingTimeInterval(60))
        #expect(storedA)
        #expect(cachedA == "token-a")
        #expect(rotatedCredentialMiss == nil)

        let storedB = cache.store("token-b", expiresIn: 60, for: credentialsB, now: now)
        let expiredB = cache.token(for: credentialsB, now: now.addingTimeInterval(31))
        let acceptedEmpty = cache.store("", expiresIn: 3_600, for: credentialsA, now: now)
        let acceptedShortLifetime = cache.store("token", expiresIn: 30, for: credentialsA, now: now)
        let acceptedInfiniteLifetime = cache.store(
            "token",
            expiresIn: .infinity,
            for: credentialsA,
            now: now
        )
        let acceptedOversizedToken = cache.store(
            String(repeating: "a", count: TailscaleClient.maximumOAuthAccessTokenBytes + 1),
            expiresIn: 3_600,
            for: credentialsA,
            now: now
        )
        #expect(storedB)
        #expect(expiredB == nil)
        #expect(!acceptedEmpty)
        #expect(!acceptedShortLifetime)
        #expect(!acceptedInfiniteLifetime)
        #expect(!acceptedOversizedToken)

        let restoredA = cache.store("token-a", expiresIn: 3_600, for: credentialsA, now: now)
        #expect(restoredA)
        cache.clear()
        let cleared = cache.token(for: credentialsA, now: now)
        #expect(cleared == nil)
    }

    @Test func recorderPreservesFragmentedUTF8Scalars() {
        var pending = Data()
        let euro = Array("€".utf8)

        #expect(SessionRecorder.decodeAvailableUTF8(&pending, appending: Data(euro.prefix(2))) == nil)
        #expect(pending.count == 2)
        #expect(SessionRecorder.decodeAvailableUTF8(&pending, appending: Data(euro.suffix(1))) == "€")
        #expect(pending.isEmpty)
    }

    @Test func recorderFilenamePolicyBindsPathToRecordingIdentity() {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let recordingID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let validFilename = "\(sessionID.uuidString)_\(recordingID.uuidString).cast"

        #expect(SessionRecorder.isValidRecordingFilename(
            validFilename,
            sessionID: sessionID,
            recordingID: recordingID
        ))
        #expect(!SessionRecorder.isValidRecordingFilename(
            "../\(validFilename)",
            sessionID: sessionID,
            recordingID: recordingID
        ))
        #expect(!SessionRecorder.isValidRecordingFilename(
            "\(sessionID.uuidString)_\(UUID().uuidString).cast",
            sessionID: sessionID,
            recordingID: recordingID
        ))
    }

    @Test @MainActor func invalidRecordingIndexBlocksStartAndDeleteWithoutTouchingFiles() throws {
        let fixtures: [(String, Data)] = [
            ("malformed", Data("not-json".utf8)),
            (
                "oversized",
                Data(repeating: 0, count: SessionRecorder.maximumRecordingIndexBytes + 1)
            )
        ]

        for (label, indexData) in fixtures {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("glas-recording-index-\(label)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }

            let recordingID = UUID()
            let sessionID = UUID()
            let filename = "\(sessionID.uuidString)_\(recordingID.uuidString).cast"
            let recording = SessionRecording(
                id: recordingID,
                sessionID: sessionID,
                serverName: "Retained",
                host: "retained.example.com",
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                endTime: Date(timeIntervalSince1970: 1_700_000_010),
                eventCount: 1,
                filename: filename,
                capturesInput: false,
                isComplete: true
            )
            let indexURL = directory.appendingPathComponent("index.json")
            let castURL = directory.appendingPathComponent(filename)
            let castData = Data("evidence-must-survive".utf8)
            try indexData.write(to: indexURL)
            try castData.write(to: castURL)
            let originalNames = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()

            let recorder = SessionRecorder(recordingsDirectory: directory)
            recorder.start(
                sessionID: UUID(),
                serverName: "Must not start",
                host: "blocked.example.com",
                width: 80,
                height: 24
            )

            #expect(!recorder.isRecording)
            #expect(recorder.lastError != nil)
            #expect(throws: SessionRecordingStorageError.self) {
                try SessionRecorder.deleteRecording(recording, at: directory)
            }
            #expect(try Data(contentsOf: indexURL) == indexData)
            #expect(try Data(contentsOf: castURL) == castData)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
                == originalNames)
            #expect(SessionRecorder.recordingCatalogLoadError != nil)
        }
    }

    @Test @MainActor func recordingDeletionRollsBackQuarantineWhenIndexWriteDoesNotCommit() throws {
        struct InjectedIndexFailure: Error {}

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glas-recording-delete-rollback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingID = UUID()
        let sessionID = UUID()
        let filename = "\(sessionID.uuidString)_\(recordingID.uuidString).cast"
        let recording = SessionRecording(
            id: recordingID,
            sessionID: sessionID,
            serverName: "Rollback",
            host: "rollback.example.com",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_010),
            eventCount: 1,
            filename: filename,
            capturesInput: false,
            isComplete: true
        )
        try SessionRecorder.saveRecordings([recording], at: directory)
        let indexURL = directory.appendingPathComponent("index.json")
        let originalIndex = try Data(contentsOf: indexURL)
        let finalURL = directory.appendingPathComponent(filename)
        let partialURL = directory.appendingPathComponent(".\(filename).partial")
        let finalData = Data("final-evidence".utf8)
        let partialData = Data("partial-evidence".utf8)
        try finalData.write(to: finalURL)
        try partialData.write(to: partialURL)

        #expect(throws: InjectedIndexFailure.self) {
            try SessionRecorder.deleteRecording(
                recording,
                at: directory,
                indexWriter: { _, _ in throw InjectedIndexFailure() }
            )
        }

        #expect(try Data(contentsOf: indexURL) == originalIndex)
        #expect(try Data(contentsOf: finalURL) == finalData)
        #expect(try Data(contentsOf: partialURL) == partialData)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(".\(filename).deleting").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(".\(filename).partial.deleting").path
        ))
    }

    @Test @MainActor func recordingDeletionAcceptsVerifiedCommitAfterWriterReportsFailure() throws {
        struct InjectedPostCommitFailure: Error {}

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glas-recording-delete-postcommit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingID = UUID()
        let sessionID = UUID()
        let filename = "\(sessionID.uuidString)_\(recordingID.uuidString).cast"
        let recording = SessionRecording(
            id: recordingID,
            sessionID: sessionID,
            serverName: "Committed",
            host: "committed.example.com",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_010),
            eventCount: 1,
            filename: filename,
            capturesInput: false,
            isComplete: true
        )
        try SessionRecorder.saveRecordings([recording], at: directory)
        let finalURL = directory.appendingPathComponent(filename)
        let partialURL = directory.appendingPathComponent(".\(filename).partial")
        try Data("final-evidence".utf8).write(to: finalURL)
        try Data("partial-evidence".utf8).write(to: partialURL)

        try SessionRecorder.deleteRecording(
            recording,
            at: directory,
            indexWriter: { recordings, directory in
                try SessionRecorder.saveRecordings(recordings, at: directory)
                throw InjectedPostCommitFailure()
            }
        )

        #expect(try SessionRecorder.verifiedRecordings(at: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: finalURL.path))
        #expect(!FileManager.default.fileExists(atPath: partialURL.path))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(".\(filename).deleting").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(".\(filename).partial.deleting").path
        ))
    }

    @Test @MainActor func recordingDeletionReconcilesCrashQuarantineFromVerifiedIndex() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glas-recording-delete-reconcile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingID = UUID()
        let sessionID = UUID()
        let filename = "\(sessionID.uuidString)_\(recordingID.uuidString).cast"
        let recording = SessionRecording(
            id: recordingID,
            sessionID: sessionID,
            serverName: "Recovery",
            host: "recovery.example.com",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_010),
            eventCount: 1,
            filename: filename,
            capturesInput: false,
            isComplete: true
        )
        let finalURL = directory.appendingPathComponent(filename)
        let quarantineURL = directory.appendingPathComponent(".\(filename).deleting")
        let evidence = Data("crash-evidence".utf8)

        try SessionRecorder.saveRecordings([recording], at: directory)
        try evidence.write(to: finalURL)
        try FileManager.default.moveItem(at: finalURL, to: quarantineURL)

        #expect(try SessionRecorder.verifiedRecordings(at: directory) == [recording])
        #expect(try Data(contentsOf: finalURL) == evidence)
        #expect(!FileManager.default.fileExists(atPath: quarantineURL.path))

        try SessionRecorder.saveRecordings([], at: directory)
        try FileManager.default.moveItem(at: finalURL, to: quarantineURL)

        #expect(try SessionRecorder.verifiedRecordings(at: directory).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: finalURL.path))
        #expect(!FileManager.default.fileExists(atPath: quarantineURL.path))
    }

    @Test @MainActor func recorderRecoveryPreservesInterruptedStateAndStableEndTime() {
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let interruptionTime = startTime.addingTimeInterval(75)
        let recordingID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let recording = SessionRecording(
            id: recordingID,
            sessionID: sessionID,
            serverName: "example",
            host: "example.com",
            startTime: startTime,
            endTime: nil,
            eventCount: 12,
            filename: "\(sessionID.uuidString)_\(recordingID.uuidString).cast",
            capturesInput: false,
            isComplete: false
        )

        let recovered = SessionRecorder.recoveredInterruptedRecording(
            recording,
            modificationDate: interruptionTime
        )
        let recoveredAgain = SessionRecorder.recoveredInterruptedRecording(
            recovered,
            modificationDate: interruptionTime.addingTimeInterval(300)
        )

        #expect(!recovered.isComplete)
        #expect(recovered.endTime == interruptionTime)
        #expect(!recoveredAgain.isComplete)
        #expect(recoveredAgain.endTime == interruptionTime)
    }

    @Test @MainActor func recorderDeletionRequiresVerifiedAbsence() throws {
        struct InjectedRemovalFailure: Error {}

        let url = URL(fileURLWithPath: "/recordings/incomplete.cast")
        var exists = true
        var removeCalls = 0

        #expect(throws: SessionRecordingStorageError.deletionNotVerified(filename: "incomplete.cast")) {
            try SessionRecorder.removeItemVerifyingAbsence(
                at: url,
                itemExists: { _ in exists },
                removeItem: { _ in removeCalls += 1 }
            )
        }
        #expect(removeCalls == 1)

        let removedDespiteProviderError = try SessionRecorder.removeItemVerifyingAbsence(
            at: url,
            itemExists: { _ in exists },
            removeItem: { _ in
                removeCalls += 1
                exists = false
                throw InjectedRemovalFailure()
            }
        )
        #expect(removedDespiteProviderError)
        #expect(removeCalls == 2)

        let alreadyAbsent = try SessionRecorder.removeItemVerifyingAbsence(
            at: url,
            itemExists: { _ in false },
            removeItem: { _ in Issue.record("Removal must not run for an absent file") }
        )
        #expect(!alreadyAbsent)
    }

    @Test @MainActor func recorderFailedDeletionRetainsIncompleteIndexEntryForRetry() throws {
        let recordingID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let recording = SessionRecording(
            id: recordingID,
            sessionID: sessionID,
            serverName: "example",
            host: "example.com",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_030),
            eventCount: 5,
            filename: "\(sessionID.uuidString)_\(recordingID.uuidString).cast",
            capturesInput: false,
            isComplete: false
        )

        let retained = SessionRecorder.updatedIndex(
            [],
            recording: recording,
            retainRecording: true
        )
        let removedAfterVerifiedDeletion = SessionRecorder.updatedIndex(
            retained,
            recording: recording,
            retainRecording: false
        )

        let retainedRecording = try #require(retained.first)
        #expect(retained.count == 1)
        #expect(retainedRecording.id == recordingID)
        #expect(!retainedRecording.isComplete)
        #expect(removedAfterVerifiedDeletion.isEmpty)
    }

    @Test func recorderAggregatePolicyBoundsCountBytesAndAgeWithoutPruning() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = SessionRecordingStoragePolicy(
            maximumCount: 2,
            maximumAggregateBytes: 100,
            maximumAge: 24 * 60 * 60
        )

        try BoundedStorage.validateRecordingCollection(
            SessionRecordingStorageUsage(
                recordingCount: 1,
                totalBytes: 99,
                oldestStartTime: now.addingTimeInterval(-24 * 60 * 60)
            ),
            now: now,
            policy: policy
        )

        #expect(throws: SessionRecordingStorageError.maximumCountReached(limit: 2)) {
            try BoundedStorage.validateRecordingCollection(
                SessionRecordingStorageUsage(
                    recordingCount: 2,
                    totalBytes: 99,
                    oldestStartTime: now
                ),
                now: now,
                policy: policy
            )
        }
        #expect(throws: SessionRecordingStorageError.maximumAggregateBytesReached(limit: 100)) {
            try BoundedStorage.validateRecordingCollection(
                SessionRecordingStorageUsage(
                    recordingCount: 1,
                    totalBytes: 100,
                    oldestStartTime: now
                ),
                now: now,
                policy: policy
            )
        }
        #expect(throws: SessionRecordingStorageError.retentionReviewRequired(maximumAgeDays: 1)) {
            try BoundedStorage.validateRecordingCollection(
                SessionRecordingStorageUsage(
                    recordingCount: 1,
                    totalBytes: 99,
                    oldestStartTime: now.addingTimeInterval(-(24 * 60 * 60 + 1))
                ),
                now: now,
                policy: policy
            )
        }
    }

    @Test func terminalPastePolicyReviewsMultilineAndLargePayloads() {
        #expect(!SwiftTermPastePolicy.requiresReview("echo safe"))
        #expect(SwiftTermPastePolicy.requiresReview("echo one\necho two"))
        #expect(SwiftTermPastePolicy.requiresReview(
            String(repeating: "a", count: SwiftTermPastePolicy.directPasteMaximumBytes + 1)
        ))
    }

    @Test func terminalPastePolicyPreservesBracketedPasteFraming() {
        let framed = SwiftTermPastePolicy.framedData(for: "one\ntwo", bracketed: true)
        #expect(framed == Data("\u{1B}[200~one\ntwo\u{1B}[201~".utf8))
        #expect(SwiftTermPastePolicy.framedData(for: "one", bracketed: false) == Data("one".utf8))
    }

    @Test func terminalPastePolicyRejectsOversizedPayloadWithoutRetainingContent() throws {
        let text = String(repeating: "x", count: SwiftTermPastePolicy.maximumPayloadBytes + 1)
        let request = try #require(SwiftTermPastePolicy.reviewRequest(for: text, bracketed: false))

        #expect(request.exceedsMaximumSize)
        #expect(request.content.isEmpty)
        #expect(!SwiftTermPastePolicy.isAllowed(text))
    }

    @Test @MainActor func terminalFontZoomIsPerTerminalBoundedAndResettable() {
        let first = SwiftTermHostModel()
        let second = SwiftTermHostModel()
        #expect(first.resolvedFontSize(defaultSize: 14) == 14)
        first.adjustFontSize(by: 1, defaultSize: 14)
        #expect(first.resolvedFontSize(defaultSize: 14) == 15)
        #expect(second.resolvedFontSize(defaultSize: 14) == 14)
        first.adjustFontSize(by: -1, defaultSize: 14)
        #expect(first.resolvedFontSize(defaultSize: 14) == 14)
        first.adjustFontSize(by: -100, defaultSize: 14)
        #expect(first.resolvedFontSize(defaultSize: 14) == 10)
        first.adjustFontSize(by: 100, defaultSize: 14)
        #expect(first.resolvedFontSize(defaultSize: 14) == 72)
        first.resetFontSize()
        #expect(first.fontSizeOverride == nil)
        #expect(first.resolvedFontSize(defaultSize: 18) == 18)
    }

    @Test @MainActor func terminalRendererPreAttachBufferIsBoundedAndReleaseClearsIt() {
        let model = SwiftTermHostModel()
        let prefix = Data("buffered-before-attach".utf8)
        model.ingest(data: prefix, nonce: 1)
        #expect(model.pendingRendererByteCount == prefix.count)
        #expect(model.droppedPendingRendererByteCount == 0)
        #expect(!model.hasRetainedRenderer)

        let overflowBytes = 19
        model.ingest(
            data: Data(
                repeating: UInt8(ascii: "x"),
                count: SwiftTermHostModel.maximumPendingRendererBytes
                    - prefix.count
                    + overflowBytes
            ),
            nonce: 2
        )
        #expect(
            model.pendingRendererByteCount
                == SwiftTermHostModel.maximumPendingRendererBytes
        )
        #expect(model.droppedPendingRendererByteCount == overflowBytes)

        model.releaseRenderer()
        #expect(model.pendingRendererByteCount == 0)
        #expect(model.droppedPendingRendererByteCount == 0)
        #expect(!model.hasRetainedRenderer)
        #expect(model.rendererDiagnostics == .awaitingWindow)
    }

    #if canImport(UIKit)
    #if os(iOS)
    @Test @MainActor func iOSTerminalWorkgroupPresentationRemainsResponsive() async throws {
        let manager = SessionManager(loadImmediately: false)
        let settings = SettingsManager(loadImmediately: false)
        let router = IOSAppRouter()
        let group = manager.createWorkgroup(name: "Presentation regression", colorTag: .blue)
        let session = TerminalSession(server: ServerConfiguration(
            name: "Presentation fixture", host: "example.invalid", port: 22, username: "test"
        ))
        manager.registerSession(session)
        _ = manager.appendSession(session, toWorkgroup: group)
        session.state = .connecting
        let root = VisionTerminalWorkgroupView(workgroupID: group)
            .environment(manager).environment(settings).environment(router)
        let controller = UIHostingController(rootView: root)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            manager.closeWorkgroup(group)
        }
        for _ in 0..<10 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(session.hasMeasuredTerminalGeometry)
        session.state = .connected
        session.feedTerminalData(Data("Presentation regression\r\n".utf8))
        try await Task.sleep(for: .milliseconds(200))
        #expect(session.terminalHostModel.hasRetainedRenderer)
        func accessoryToolbar(in view: UIView) -> UIToolbar? {
            if let toolbar = view.inputAccessoryView as? UIToolbar { return toolbar }
            for child in view.subviews {
                if let toolbar = accessoryToolbar(in: child) { return toolbar }
            }
            return nil
        }
        let accessory = try #require(accessoryToolbar(in: controller.view))
        // Dismiss, spacing, hosted app tools, cursor pad, spacing, special keys.
        #expect(accessory.items?.count == 6)
        #expect(accessory.items?[2].customView?.bounds.width == 100)
        #expect(accessory.intrinsicContentSize.height == 60)
        let keysMenu = try #require(accessory.items?.last?.menu)
        #expect(!keysMenu.children.contains { $0.title == "Navigation" })
        let second = TerminalSession(server: session.server)
        manager.registerSession(second)
        _ = manager.appendSession(second, toWorkgroup: group)
        second.state = .connected
        for active in [second, session, second, session] {
            manager.selectSession(active.id, inWorkgroup: group)
            try await Task.sleep(for: .milliseconds(100))
            controller.view.layoutIfNeeded()
            #expect(manager.selectedSession(inWorkgroup: group)?.id == active.id)
        }
        session.terminalHostModel.adjustFontSize(by: 1, defaultSize: 14)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.terminalHostModel.resolvedFontSize(defaultSize: 14) == 15)
        session.terminalHostModel.resetFontSize()
        #expect(session.terminalHostModel.resolvedFontSize(defaultSize: 14) == 14)
    }
    #endif
    #if os(visionOS)
    @Test func visionTerminalStatusMatchesMacOverviewRules() {
        #expect(VisionTerminalStatus.color(for: .connected) == Color.green)
        #expect(VisionTerminalStatus.color(for: .connecting) == Color.orange)
        #expect(VisionTerminalStatus.color(for: .reconnecting) == Color.orange)
        #expect(VisionTerminalStatus.color(for: .error("Test failure")) == Color.red)
        #expect(VisionTerminalStatus.color(for: .disconnected) == Color.secondary)
    }

    @Test @MainActor func visionWorkgroupRepeatedPresentationTransitionsRetainTerminals() async throws {
        for sessionCount in [1, 3] {
            try await verifyVisionWorkgroupTransitions(sessionCount: sessionCount)
        }
    }

    private func verifyVisionWorkgroupTransitions(sessionCount: Int) async throws {
        let manager = SessionManager(loadImmediately: false)
        let settings = SettingsManager(loadImmediately: false)
        let group = manager.createWorkgroup(name: "Spatial transition test", colorTag: .blue)
        var sentBytes = 0
        let sessions = (1...sessionCount).map { index in
            let session = TerminalSession(
                server: ServerConfiguration(name: "Terminal \(index)", host: "example.invalid", port: 22, username: "test"),
                terminalWriteSink: { sentBytes += $0.count }
            )
            manager.registerSession(session)
            _ = manager.appendSession(session, toWorkgroup: group)
            session.state = .connected
            session.feedTerminalData(Data("Terminal \(index) — live renderer fixture\r\n".utf8))
            return session
        }
        let state = VisionTerminalPresentationState()
        let root = VisionTerminalWorkgroupView(workgroupID: group, spatialPresentation: state)
            .environment(manager).environment(settings)
        let controller = UIHostingController(rootView: root)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = controller.view.frame
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            manager.closeWorkgroup(group)
        }
        func settle() async throws {
            for _ in 0..<8 {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
            }
        }
        try await settle()
        let geometries = sessions.map(\.currentTerminalGeometry)
        for _ in 0..<6 {
            for mode in [VisionTerminalPresentation.grid, .carousel, .tabs] {
                state.mode = mode
                try await settle()
                #expect(state.mode == (sessionCount == 1 ? .tabs : mode))
                #expect(manager.sessions(inWorkgroup: group).map(\.id) == sessions.map(\.id))
                #expect(sessions.map(\.currentTerminalGeometry) == geometries)
                for session in sessions {
                    #expect(session.terminalHostModel.previewImage(maxPixelWidth: 200) != nil)
                }
                if state.mode != .tabs {
                    #expect(sessions.allSatisfy { !$0.terminalHostModel.allowsFocusOwnership })
                }
            }
        }
        #expect(sentBytes == 0)
    }

    @Test @MainActor func visionPreviewWithoutRendererDoesNotConsumeOutput() {
        let model = SwiftTermHostModel()
        let data = Data("pending terminal output".utf8)
        model.ingest(data: data, nonce: 1)
        #expect(model.previewImage() == nil)
        #expect(model.pendingRendererByteCount == data.count)
        #expect(model.rendererDiagnostics.backend == .awaitingWindow)
    }

    @Test @MainActor func visionPreviewIsBoundedReadOnlyAndPreservesGeometry() async throws {
        let model = SwiftTermHostModel()
        var sentBytes = 0
        var resizeEvents = 0
        let host = SwiftTermHostView(
            model: model,
            theme: SwiftTermTheme(fontSize: 14, foreground: (1, 1, 1),
                                  background: (0, 0, 0, 0), cursor: (1, 1, 1)),
            runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "Block", blinkingCursor: false, scrollbackLines: 500),
            allowsFocusOwnership: false,
            onSendData: { sentBytes += $0.count },
            onResize: { _, _ in resizeEvents += 1 }
        )
        let controller = UIHostingController(rootView: host.opacity(0))
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = controller.view.frame
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<20 {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        model.ingest(data: Data("live preview without input".utf8), nonce: 1)
        for _ in 0..<20 {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        let before = resizeEvents
        let text = model.getVisibleText()
        let image = try #require(model.previewImage(maxPixelWidth: 400))
        #expect(image.size.width <= 400)
        #expect(image.size.height <= 640)
        #expect(image.scale == 1)
        #expect(model.getVisibleText() == text)
        #expect(resizeEvents == before)
        #expect(sentBytes == 0)
        #expect(!model.allowsFocusOwnership)
        let pixels = try #require(image.cgImage?.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(pixels))
        let count = CFDataGetLength(pixels)
        #expect((0..<count).contains { bytes[$0] != 0 })
    }
    #endif

    @Test func terminalRendererDiagnosticsDoNotInventUnobservedBackingState() {
        let model = SwiftTermHostModel()

        #expect(model.rendererDiagnostics.backend == .awaitingWindow)
        #expect(!model.rendererDiagnostics.isWindowAttached)
        #expect(model.rendererDiagnostics.hostBackingIsClear == nil)
        #expect(model.rendererDiagnostics.rendererBackingIsClear == nil)
        #expect(model.rendererDiagnostics.preservesTransparentBacking == nil)
        #expect(model.rendererDiagnostics.failureDescription == nil)
    }

    @Test @MainActor func terminalHostAppliesInitialFocusOwnershipBeforeAttachment() throws {
        let model = SwiftTermHostModel()
        let hostView = SwiftTermHostView(
            model: model,
            theme: SwiftTermTheme(
                fontSize: 14,
                foreground: (1, 1, 1),
                background: (0, 0, 0, 0),
                cursor: (1, 1, 1)
            ),
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: "Block",
                blinkingCursor: true,
                scrollbackLines: 500
            ),
            allowsFocusOwnership: false,
            onSendData: { _ in },
            onResize: { _, _ in }
        )
        let controller = UIHostingController(rootView: hostView)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let windowScene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = controller.view.frame
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        #expect(model.allowsFocusOwnership == false)
        window.isHidden = true
    }

    @Test func terminalHardwareKeyPolicyUsesCorrectXtermSequences() {
        #expect(
            SwiftTermHardwareKeyPolicy.legacyFunctionKeySequence(for: .keyboardF10)
                == Array("\u{1B}[21~".utf8)
        )
        #expect(
            SwiftTermHardwareKeyPolicy.legacyFunctionKeySequence(for: .keyboardF12)
                == Array("\u{1B}[24~".utf8)
        )
        #expect(
            SwiftTermHardwareKeyPolicy.legacyFunctionKeySequence(for: .keyboardF13)
                == Array("\u{1B}[25~".utf8)
        )
        #expect(
            SwiftTermHardwareKeyPolicy.legacyFunctionKeySequence(for: .keyboardF24)
                == Array("\u{1B}[45~".utf8)
        )
        #expect(SwiftTermHardwareKeyPolicy.legacyFunctionKeySequence(for: .keyboardF9) == nil)
        #expect(!SwiftTermRuntimeSettings(
            cursorStyle: "Block",
            blinkingCursor: true,
            scrollbackLines: 500
        ).optionAsMetaKey)
    }

    @Test func terminalContextualKeyPolicyPreservesApplicationCursorAndFunctionSequences() {
        #expect(SwiftTermSpecialKeyPolicy.sequence(for: .escape) == [0x1b])
        #expect(SwiftTermSpecialKeyPolicy.sequence(for: .tab) == [0x09])
        #expect(
            SwiftTermSpecialKeyPolicy.sequence(for: .left(applicationCursor: false))
                == Array("\u{1B}[D".utf8)
        )
        #expect(
            SwiftTermSpecialKeyPolicy.sequence(for: .left(applicationCursor: true))
                == Array("\u{1B}OD".utf8)
        )
        #expect(
            SwiftTermSpecialKeyPolicy.sequence(for: .function(12))
                == Array("\u{1B}[24~".utf8)
        )
        #expect(SwiftTermSpecialKeyPolicy.sequence(for: .function(0)) == nil)
        #expect(SwiftTermSpecialKeyPolicy.sequence(for: .function(13)) == nil)
    }

    @Test func terminalCursorScrubDeadZoneAndDominantAxisAreCellRelative() {
        #expect(SwiftTermCursorScrubPolicy.dominantAxis(
            horizontalPoints: 4,
            verticalPoints: 8,
            cellWidth: 10,
            cellHeight: 20
        ) == nil)
        #expect(SwiftTermCursorScrubPolicy.keys(
            for: .zero,
            applicationCursor: false
        ).isEmpty)
        #expect(SwiftTermCursorScrubPolicy.dominantAxis(
            horizontalPoints: 9,
            verticalPoints: 10,
            cellWidth: 10,
            cellHeight: 20
        ) == .horizontal)
        #expect(SwiftTermCursorScrubPolicy.dominantAxis(
            horizontalPoints: 5,
            verticalPoints: 16,
            cellWidth: 10,
            cellHeight: 20
        ) == .vertical)
        #expect(SwiftTermCursorScrubPolicy.dominantAxis(
            horizontalPoints: 20,
            verticalPoints: 20,
            cellWidth: 0,
            cellHeight: 20
        ) == nil)
    }

    @Test func terminalCursorScrubQuantizesOnlyTheLockedAxis() {
        #expect(SwiftTermCursorScrubPolicy.quantizedDelta(
            horizontalPoints: 27,
            verticalPoints: -41,
            cellWidth: 9,
            cellHeight: 20,
            lockedAxis: .horizontal
        ) == SwiftTermCursorScrubDelta(horizontal: 3, vertical: 0))
        #expect(SwiftTermCursorScrubPolicy.quantizedDelta(
            horizontalPoints: 27,
            verticalPoints: -41,
            cellWidth: 9,
            cellHeight: 20,
            lockedAxis: .vertical
        ) == SwiftTermCursorScrubDelta(horizontal: 0, vertical: -2))
        #expect(SwiftTermCursorScrubPolicy.quantizedDelta(
            horizontalPoints: 10_000,
            verticalPoints: 0,
            cellWidth: 1,
            cellHeight: 1,
            lockedAxis: .horizontal
        ) == SwiftTermCursorScrubDelta(
            horizontal: SwiftTermCursorScrubPolicy.maximumStepsPerAxis,
            vertical: 0
        ))
    }

    @Test func terminalCursorScrubCanTurnWithoutLifting() {
        let up = SwiftTermCursorScrubPolicy.freeformDelta(
            horizontalPoints: 0, verticalPoints: -40, cellWidth: 10, cellHeight: 20
        )
        let right = SwiftTermCursorScrubPolicy.freeformDelta(
            horizontalPoints: 30, verticalPoints: -40, cellWidth: 10, cellHeight: 20
        )
        let left = SwiftTermCursorScrubPolicy.freeformDelta(
            horizontalPoints: 10, verticalPoints: -40, cellWidth: 10, cellHeight: 20
        )
        #expect(up == SwiftTermCursorScrubDelta(horizontal: 0, vertical: -2))
        #expect(SwiftTermCursorScrubPolicy.incrementalDelta(current: right, previouslyApplied: up)
            == SwiftTermCursorScrubDelta(horizontal: 3, vertical: 0))
        #expect(SwiftTermCursorScrubPolicy.incrementalDelta(current: left, previouslyApplied: right)
            == SwiftTermCursorScrubDelta(horizontal: -2, vertical: 0))
    }

    @Test func terminalCursorScrubCapsUpdatesAndPreservesReversalRemainder() {
        let first = SwiftTermCursorScrubPolicy.incrementalDelta(
            current: SwiftTermCursorScrubDelta(horizontal: 20, vertical: 0),
            previouslyApplied: .zero
        )
        #expect(first == SwiftTermCursorScrubDelta(
            horizontal: SwiftTermCursorScrubPolicy.maximumStepsPerUpdate,
            vertical: 0
        ))

        let partiallyApplied = SwiftTermCursorScrubPolicy.adding(first, to: .zero)
        let second = SwiftTermCursorScrubPolicy.incrementalDelta(
            current: SwiftTermCursorScrubDelta(horizontal: 20, vertical: 0),
            previouslyApplied: partiallyApplied
        )
        #expect(second == first)

        let reversal = SwiftTermCursorScrubPolicy.incrementalDelta(
            current: SwiftTermCursorScrubDelta(horizontal: -3, vertical: 0),
            previouslyApplied: SwiftTermCursorScrubDelta(horizontal: 2, vertical: 0)
        )
        #expect(reversal == SwiftTermCursorScrubDelta(
            horizontal: -SwiftTermCursorScrubPolicy.maximumStepsPerUpdate,
            vertical: 0
        ))
        let reversalProgress = SwiftTermCursorScrubPolicy.adding(
            reversal,
            to: SwiftTermCursorScrubDelta(horizontal: 2, vertical: 0)
        )
        #expect(reversalProgress == SwiftTermCursorScrubDelta(horizontal: -2, vertical: 0))
        #expect(SwiftTermCursorScrubPolicy.incrementalDelta(
            current: SwiftTermCursorScrubDelta(horizontal: -3, vertical: 0),
            previouslyApplied: reversalProgress
        ) == SwiftTermCursorScrubDelta(horizontal: -1, vertical: 0))

        let fastDragTarget = SwiftTermCursorScrubDelta(horizontal: 23, vertical: 0)
        var fastDragApplied = SwiftTermCursorScrubDelta.zero
        var emittedSteps = 0
        while fastDragApplied != fastDragTarget {
            let batch = SwiftTermCursorScrubPolicy.incrementalDelta(
                current: fastDragTarget,
                previouslyApplied: fastDragApplied
            )
            #expect(abs(batch.horizontal) <= SwiftTermCursorScrubPolicy.maximumStepsPerUpdate)
            emittedSteps += batch.horizontal
            fastDragApplied = SwiftTermCursorScrubPolicy.adding(batch, to: fastDragApplied)
        }
        #expect(emittedSteps == fastDragTarget.horizontal)
    }

    @Test func terminalCursorScrubDirectionsPreserveApplicationCursorMode() {
        let delta = SwiftTermCursorScrubDelta(horizontal: -2, vertical: 1)
        #expect(SwiftTermCursorScrubPolicy.keys(
            for: delta,
            applicationCursor: false
        ) == [
            .left(applicationCursor: false),
            .left(applicationCursor: false),
            .down(applicationCursor: false),
        ])
        #expect(SwiftTermCursorScrubPolicy.sequences(
            for: delta,
            applicationCursor: false
        ) == [
            Array("\u{1B}[D".utf8),
            Array("\u{1B}[D".utf8),
            Array("\u{1B}[B".utf8),
        ])
        #expect(SwiftTermCursorScrubPolicy.sequences(
            for: delta,
            applicationCursor: true
        ) == [
            Array("\u{1B}OD".utf8),
            Array("\u{1B}OD".utf8),
            Array("\u{1B}OB".utf8),
        ])
    }

    @Test @MainActor func terminalRendererDrawsGlyphsAfterWindowAttachmentWithClearBacking() async throws {
        let model = SwiftTermHostModel()
        var ansiColors = Array(
            repeating: SwiftTermThemeColor(red: 0, green: 0, blue: 0),
            count: 16
        )
        ansiColors[1] = SwiftTermThemeColor(red: 0, green: 1, blue: 0)
        let hostView = SwiftTermHostView(
            model: model,
            theme: SwiftTermTheme(
                fontSize: 14,
                foreground: (1, 0, 1),
                background: (0, 0, 0, 0),
                cursor: (0, 0, 1),
                ansiColors: ansiColors
            ),
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: "Block",
                blinkingCursor: true,
                scrollbackLines: 500
            ),
            onSendData: { _ in },
            onResize: { _, _ in }
        )
        let controller = UIHostingController(rootView: hostView)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)

        let detachedDiagnostics = model.rendererDiagnostics
        #expect(detachedDiagnostics.backend == .awaitingWindow)
        #expect(!detachedDiagnostics.isWindowAttached)
        #expect(detachedDiagnostics.hostBackingIsClear == nil)
        #expect(detachedDiagnostics.rendererBackingIsClear == nil)
        #expect(detachedDiagnostics.failureDescription == nil)

        let windowScene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = controller.view.frame
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        for _ in 0..<20 where model.rendererDiagnostics.backend == .awaitingWindow {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }

        let attachedDiagnostics = model.rendererDiagnostics
        #expect(attachedDiagnostics.isWindowAttached)
        #if os(visionOS)
        #expect(attachedDiagnostics.backend == .coreGraphics)
        #expect(attachedDiagnostics.failureDescription == nil)
        #expect(attachedDiagnostics.rendererBackingIsClear == nil)
        #elseif canImport(MetalKit)
        #expect(attachedDiagnostics.backend == .metal)
        #expect(attachedDiagnostics.failureDescription == nil)
        #expect(attachedDiagnostics.rendererBackingIsClear == true)
        #else
        #expect(attachedDiagnostics.backend == .coreGraphicsFallback)
        #expect(attachedDiagnostics.failureDescription != nil)
        #expect(attachedDiagnostics.rendererBackingIsClear == nil)
        #endif
        #expect(attachedDiagnostics.hostBackingIsClear == true)
        #expect(attachedDiagnostics.preservesTransparentBacking == true)

        #if os(visionOS)
        model.ingest(data: Data("MMMMMMMM\u{1B}[31mGGGGGGGG\u{1B}[0m".utf8), nonce: 1)
        for _ in 0..<20 where !(model.getVisibleText().last?.contains("MMMMMMMMGGGGGGGG") ?? false) {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }
        #expect(model.getVisibleText().last?.contains("MMMMMMMMGGGGGGGG") == true)

        let rootView = try #require(controller.view)
        var pendingViews = [rootView]
        var terminalView: UIView?
        while let view = pendingViews.popLast() {
            if view.isAccessibilityElement, view.accessibilityLabel == "Terminal" {
                terminalView = view
                break
            }
            pendingViews.append(contentsOf: view.subviews)
        }

        let renderedView = try #require(terminalView)
        renderedView.setNeedsDisplay()
        renderedView.layoutIfNeeded()
        await Task.yield()

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: renderedView.bounds, format: format)
        let image = renderer.image { rendererContext in
            renderedView.layer.render(in: rendererContext.cgContext)
        }

        let cgImage = try #require(image.cgImage)
        let pixelData = try #require(cgImage.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(pixelData))
        #expect(cgImage.bitsPerPixel == 32)

        var magentaPixelCount = 0
        var greenPixelCount = 0
        var transparentPixelCount = 0
        var minimumMagentaX = cgImage.width
        var maximumMagentaX = 0
        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                let offset = (y * cgImage.bytesPerRow) + (x * 4)
                let firstColor = bytes[offset]
                let green = bytes[offset + 1]
                let thirdColor = bytes[offset + 2]
                let alpha = bytes[offset + 3]
                if alpha < 8 {
                    transparentPixelCount += 1
                }
                // Magenta is symmetric in RGBA and BGRA, so this remains valid
                // for either UIKit byte ordering.
                if firstColor > 191, green < 64, thirdColor > 191, alpha > 64 {
                    magentaPixelCount += 1
                    minimumMagentaX = min(minimumMagentaX, x)
                    maximumMagentaX = max(maximumMagentaX, x)
                }
                if firstColor < 64, green > 191, thirdColor < 64, alpha > 64 {
                    greenPixelCount += 1
                }
            }
        }

        #expect(magentaPixelCount > 100)
        #expect(greenPixelCount > 100)
        #expect(maximumMagentaX - minimumMagentaX > 56)
        #expect(transparentPixelCount > 100)
        #endif
    }

    @Test func terminalITermFileReferenceRetainsOnlyBoundedMetadata() throws {
        let content = Array(
            "File=name=cmVwb3J0LnR4dA==;size=5;inline=0:SGVsbG8=".utf8
        )

        let kind = SwiftTermITermContentPolicy.semanticEventKind(for: content[...])
        guard case .fileReference(let reference) = kind else {
            Issue.record("Expected a file-reference semantic event")
            return
        }

        #expect(reference.suggestedName == "report.txt")
        #expect(reference.declaredByteCount == 5)
        #expect(reference.encodedPayloadByteCount == 8)
        #expect(!reference.requestsInlineDisplay)

        let unknownContent = Array("SetUserVar=token=cmVkYWN0ZWQ=".utf8)
        let unknownKind = SwiftTermITermContentPolicy.semanticEventKind(for: unknownContent[...])
        guard case .unhandledITermContent(let command, let byteCount) = unknownKind else {
            Issue.record("Expected an unhandled iTerm-content semantic event")
            return
        }
        #expect(command == "SetUserVar")
        #expect(byteCount == unknownContent.count)
    }

    @Test func terminalOSC52PolicyDeniesEveryRequestFormWithoutDecodingContent() {
        let write = SwiftTermOSC52Policy.evaluate(Array("c;SGVsbG8=".utf8)[...])
        #expect(write.disposition == .deniedWrite)
        #expect(write.encodedPayloadByteCount == 8)

        let query = SwiftTermOSC52Policy.evaluate(Array("c;?".utf8)[...])
        #expect(query.disposition == .deniedReadQuery)

        let unsupported = SwiftTermOSC52Policy.evaluate(Array("p;SGVsbG8=".utf8)[...])
        #expect(unsupported.disposition == .deniedUnsupportedSelection)

        let malformed = SwiftTermOSC52Policy.evaluate(Array("c;not base64".utf8)[...])
        #expect(malformed.disposition == .rejectedMalformed)

        let oversized = Array("c;".utf8) + Array(
            repeating: UInt8(ascii: "A"),
            count: SwiftTermOSC52Policy.maximumEncodedPayloadBytes + 4
        )
        let oversizedDecision = SwiftTermOSC52Policy.evaluate(oversized[...])
        #expect(oversizedDecision.disposition == .rejectedOversized)
        #expect(oversizedDecision.requestByteCount == oversized.count)
    }

    @Test @MainActor func terminalSemanticEventsFlowFromSwiftTermCallbacks() async throws {
        let model = SwiftTermHostModel()
        var streamedEvents: [SwiftTermSemanticEvent] = []
        var emittedData: [Data] = []
        let subscription = model.semanticEventPublisher.sink { event in
            streamedEvents.append(event)
        }
        defer { subscription.cancel() }
        let hostView = SwiftTermHostView(
            model: model,
            theme: SwiftTermTheme(
                fontSize: 14,
                foreground: (1, 1, 1),
                background: (0, 0, 0, 0),
                cursor: (1, 1, 1)
            ),
            runtimeSettings: SwiftTermRuntimeSettings(
                cursorStyle: "Block",
                blinkingCursor: true,
                scrollbackLines: 500
            ),
            onSendData: { emittedData.append($0) },
            onResize: { _, _ in }
        )
        let controller = UIHostingController(rootView: hostView)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)

        let windowScene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = controller.view.frame
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for _ in 0..<20 where model.rendererDiagnostics.hostBackingIsClear == nil {
            controller.view.layoutIfNeeded()
            await Task.yield()
        }

        let terminalInput = [
            Data("\u{1B}]7;file://vision-pro/private/tmp\u{07}".utf8),
            Data(
                "\u{1B}]1337;File=name=cmVwb3J0LnR4dA==;size=5;inline=0:SGVsbG8=\u{07}".utf8
            ),
            Data("terminal output".utf8),
            Data("\u{1B}]52;c;SGVs".utf8),
            Data("bG8=\u{07}".utf8)
        ]
        for (index, data) in terminalInput.enumerated() {
            model.ingest(data: data, nonce: UInt64(index + 1))
        }

        for _ in 0..<40 {
            let hasWorkingDirectory = model.semanticEvents.contains { event in
                guard case .workingDirectoryChanged(let directory) = event.kind else { return false }
                return directory == "file://vision-pro/private/tmp"
            }
            let hasFileReference = model.semanticEvents.contains { event in
                guard case .fileReference(let reference) = event.kind else { return false }
                return reference.suggestedName == "report.txt"
                    && reference.declaredByteCount == 5
            }
            let hasDisplayRange = model.semanticEvents.contains { event in
                if case .displayRangeChanged = event.kind { return true }
                return false
            }
            let hasOSC52Denial = model.semanticEvents.contains { event in
                guard case .osc52Denied(let decision) = event.kind else { return false }
                return decision.disposition == .deniedWrite
                    && decision.encodedPayloadByteCount == 8
            }
            if hasWorkingDirectory && hasFileReference && hasDisplayRange && hasOSC52Denial {
                break
            }
            controller.view.layoutIfNeeded()
            await Task.yield()
        }

        let events = model.semanticEvents
        #expect(events.count <= SwiftTermHostModel.semanticEventHistoryLimit)
        #expect(Array(streamedEvents.suffix(events.count)) == events)
        #expect(events.allSatisfy {
            $0.schemaVersion == SwiftTermSemanticEvent.currentSchemaVersion
        })
        #expect(events.map(\.sequence) == events.map(\.sequence).sorted())
        #expect(events.contains { event in
            guard case .workingDirectoryChanged(let directory) = event.kind else { return false }
            return directory == "file://vision-pro/private/tmp"
        })
        #expect(events.contains { event in
            guard case .fileReference(let reference) = event.kind else { return false }
            return reference.suggestedName == "report.txt"
                && reference.declaredByteCount == 5
                && reference.encodedPayloadByteCount == 8
        })
        #expect(events.contains { event in
            if case .displayRangeChanged(let startY, let endY) = event.kind {
                return startY <= endY
            }
            return false
        })
        #expect(events.contains { event in
            guard case .osc52Denied(let decision) = event.kind else { return false }
            return decision.disposition == .deniedWrite
                && decision.requestByteCount == 10
                && decision.encodedPayloadByteCount == 8
        })

        func descendants(of view: UIView) -> [UIView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        guard let terminalView = descendants(of: controller.view).first(where: {
            $0.accessibilityLabel == "Terminal"
        }) else {
            Issue.record("The hosted SwiftTerm view was not exposed as a terminal accessibility element")
            return
        }
        guard let textInput = terminalView as? any UITextInput else {
            Issue.record("The hosted SwiftTerm view does not conform to UITextInput")
            return
        }

        #expect(terminalView.isAccessibilityElement)
        #expect(terminalView.accessibilityValue?.contains("terminal output") == true)
        #expect(model.performanceDiagnostics.receivedChunkCount == UInt64(terminalInput.count))
        #expect(
            model.performanceDiagnostics.receivedByteCount
                == UInt64(terminalInput.reduce(0) { $0 + $1.count })
        )
        #expect(
            model.performanceDiagnostics.totalFeedDurationNanoseconds
                >= model.performanceDiagnostics.maximumFeedDurationNanoseconds
        )

        let inputChunkBaseline = model.performanceDiagnostics.emittedInputChunkCount
        let inputByteBaseline = model.performanceDiagnostics.emittedInputByteCount
        let emittedDataBaseline = emittedData.count
        textInput.setMarkedText("点", selectedRange: NSRange(location: 1, length: 0))
        #expect(model.isComposingText)
        #expect(emittedData.count == emittedDataBaseline)
        textInput.unmarkText()
        #expect(!model.isComposingText)
        #expect(emittedData.last == Data("点".utf8))
        #expect(
            model.performanceDiagnostics.emittedInputChunkCount
                == inputChunkBaseline + 1
        )
        #expect(
            model.performanceDiagnostics.emittedInputByteCount
                == inputByteBaseline + UInt64(Data("点".utf8).count)
        )

        let committedDataCount = emittedData.count
        textInput.setMarkedText("取消", selectedRange: NSRange(location: 2, length: 0))
        #expect(model.isComposingText)
        textInput.setMarkedText(nil, selectedRange: NSRange(location: 0, length: 0))
        #expect(!model.isComposingText)
        #expect(emittedData.count == committedDataCount)
    }
    #endif

    #if canImport(AppKit)
    @Test @MainActor func remoteRendererFlushesOnceAndSurvivesHostReconstructionUntilClose()
        async
    {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Retained remote",
            host: "example.com",
            username: "tester"
        ))
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false
        )
        manager.registerSession(session)
        let model = session.terminalHostModel
        let markerA = "renderer-lifetime-marker-A"
        let markerB = "renderer-lifetime-marker-B"
        let titleA = "renderer-title-A"
        let titleB = "renderer-title-B"
        let dataA = Data("\(markerA)\r\n".utf8)
        let titleDataA = Data("\u{1B}]0;\(titleA)\u{07}".utf8)
        let dataB = Data("\(markerB)\r\n".utf8)
        let titleDataB = Data("\u{1B}]0;\(titleB)\u{07}".utf8)
        let bellData = Data([0x07])
        let expectedReceivedBytes = UInt64(
            dataA.count + titleDataA.count + dataB.count + titleDataB.count + bellData.count
        )

        // Exercise the real session-to-model path before any renderer exists.
        session.feedTerminalData(dataA)
        for _ in 0..<100 where model.pendingRendererByteCount != dataA.count {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.pendingRendererByteCount == dataA.count)
        #expect(!model.hasRetainedRenderer)

        let theme = SwiftTermTheme(
            fontSize: 13,
            foreground: (1, 1, 1),
            background: (0, 0, 0, 0),
            cursor: (1, 1, 1)
        )
        let runtimeSettings = SwiftTermRuntimeSettings(
            cursorStyle: "block",
            blinkingCursor: false,
            scrollbackLines: 100
        )
        var firstTitles: [String] = []
        var secondTitles: [String] = []
        var firstBellCount = 0
        var secondBellCount = 0
        var hostingView: NSHostingView<SwiftTermHostView>? = NSHostingView(
            rootView: SwiftTermHostView(
                model: model,
                theme: theme,
                runtimeSettings: runtimeSettings,
                onSendData: { _ in },
                onResize: { _, _ in },
                onTitleChanged: { firstTitles.append($0) },
                onBell: { firstBellCount += 1 }
            )
        )
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 800, height: 600))
        hostingView?.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = hostingView
        hostingView?.layoutSubtreeIfNeeded()
        await Task.yield()

        #expect(model.hasRetainedRenderer)
        for _ in 0..<100 where model.pendingRendererByteCount != 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.pendingRendererByteCount == 0)
        session.feedTerminalData(titleDataA)
        for _ in 0..<100 where !firstTitles.contains(titleA) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(firstTitles.contains(titleA))

        window.contentView = nil
        hostingView = nil
        await Task.yield()
        #expect(manager.session(for: session.id) === session)
        #expect(model.hasRetainedRenderer)

        // The retained emulator keeps consuming transport bytes while no
        // representable is mounted.
        session.feedTerminalData(dataB)
        for _ in 0..<100 where model.performanceDiagnostics.receivedChunkCount < 3 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        hostingView = NSHostingView(
            rootView: SwiftTermHostView(
                model: model,
                theme: theme,
                runtimeSettings: runtimeSettings,
                onSendData: { _ in },
                onResize: { _, _ in },
                onTitleChanged: { secondTitles.append($0) },
                onBell: { secondBellCount += 1 }
            )
        )
        hostingView?.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = hostingView
        hostingView?.layoutSubtreeIfNeeded()
        await Task.yield()
        session.feedTerminalData(titleDataB)
        for _ in 0..<100 where !secondTitles.contains(titleB) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        session.feedTerminalData(bellData)
        for _ in 0..<100 where model.performanceDiagnostics.receivedChunkCount < 5 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let visibleText = model.getVisibleText(lastNLines: 100).joined(separator: "\n")
        #expect(visibleText.components(separatedBy: markerA).count - 1 == 1)
        #expect(visibleText.components(separatedBy: markerB).count - 1 == 1)
        #expect(firstTitles == [titleA])
        #expect(secondTitles == [titleB])
        #expect(firstBellCount == 0)
        #expect(secondBellCount == 1)
        #expect(model.performanceDiagnostics.receivedChunkCount == 5)
        #expect(model.performanceDiagnostics.receivedByteCount == expectedReceivedBytes)

        manager.closeSession(session)
        #expect(manager.session(for: session.id) == nil)
        #expect(!model.hasRetainedRenderer)
        window.contentView = nil
        hostingView = nil
        window.close()
    }
    #endif

    @Test func terminalExternalLinkPolicyAllowsOnlyBoundedCredentialFreeWebURLs() throws {
        let request = try #require(SwiftTermExternalLinkPolicy.validatedRequest(
            for: "HTTPS://ExAmPle.com:8443/path?q=1#section"
        ))

        #expect(request.url.scheme == "https")
        #expect(request.normalizedHost == "example.com")
        #expect(request.port == 8443)
        #expect(request.exactURL == "https://ExAmPle.com:8443/path?q=1#section")

        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "javascript:alert(1)") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "file:///etc/passwd") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "https://user:secret@example.com") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "https:///missing-host") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: " https://example.com") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "https://example.com/\nnext") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "https://example.com%0A.evil") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "https://example.com%0D.evil") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(for: "https://example.com%E2%80%AE.evil") == nil)
        #expect(SwiftTermExternalLinkPolicy.validatedRequest(
            for: "https://example.com/" + String(
                repeating: "a",
                count: SwiftTermExternalLinkPolicy.maximumURLBytes
            )
        ) == nil)
    }

    @Test func generatedCommandConfirmationKeepsTheReviewedExactSnapshot() {
        var editableCommand = "rm -rf ./build"
        let confirmation = GeneratedCommandConfirmation(command: editableCommand)
        editableCommand = "pwd"

        #expect(confirmation.exactCommand == "rm -rf ./build")
        #expect(confirmation.assessment.requiresConfirmation)
        #expect(confirmation.assessment.reasons.contains("Destructive or system-modifying utility"))
        #expect(editableCommand != confirmation.exactCommand)
    }

    @Test func terminalRuntimeSettingsClampScrollbackAtBothBounds() {
        #expect(SwiftTermRuntimeSettings(
            cursorStyle: "Block",
            blinkingCursor: true,
            scrollbackLines: -1
        ).scrollbackLines == 0)
        #expect(SwiftTermRuntimeSettings(
            cursorStyle: "Block",
            blinkingCursor: true,
            scrollbackLines: 100_000
        ).scrollbackLines == 100_000)
        #expect(SwiftTermRuntimeSettings(
            cursorStyle: "Block",
            blinkingCursor: true,
            scrollbackLines: Int.max
        ).scrollbackLines == 100_000)
    }

    @Test @MainActor func settingsMigrationPrefersCanonicalOpacityAndBoundsScrollback() {
        #expect(SettingsManager.resolvedWindowOpacity(canonical: 0.25, legacy: 0.9) == 0.25)
        #expect(SettingsManager.resolvedWindowOpacity(canonical: nil, legacy: 0.9) == 0.9)
        #expect(SettingsManager.resolvedWindowOpacity(canonical: 2, legacy: nil) == 1)
        #expect(SettingsManager.resolvedWindowOpacity(canonical: -1, legacy: nil) == 0)
        #expect(SettingsManager.resolvedWindowOpacity(canonical: Double.infinity, legacy: 0.9) == 0)
        #expect(SettingsManager.resolvedWindowOpacity(canonical: true, legacy: 0.9) == 0)
        #expect(SettingsManager.resolvedWindowOpacity(canonical: "opaque", legacy: 0.9) == 0)
        #expect(SettingsManager.clampedScrollbackLines(-1) == 0)
        #expect(SettingsManager.clampedScrollbackLines(10_000) == 10_000)
        #expect(SettingsManager.clampedScrollbackLines(Int.max) == 100_000)
    }

    @Test @MainActor func terminalGlassAppearancePreservesIndependentEndpointMatrix() {
        let cases: [(opacity: Double, blur: Double, paints: Bool, frosts: Bool, transparent: Bool)] = [
            (0, 0, false, false, true),
            (0, 1, false, true, false),
            (1, 0, true, false, false),
            (1, 1, true, true, false)
        ]

        for value in cases {
            let appearance = TerminalGlassAppearance(opacity: value.opacity, blur: value.blur)
            #expect(appearance.opacity == value.opacity)
            #expect(appearance.blur == value.blur)
            #expect(appearance.paintsTheme == value.paints)
            #expect(appearance.compositesBlur == value.frosts)
            #expect(appearance.isFullyTransparent == value.transparent)
        }

        #expect(TerminalGlassAppearance(opacity: -1, blur: 2) == .init(opacity: 0, blur: 1))
        #expect(TerminalGlassAppearance(opacity: .nan, blur: .infinity) == .init(opacity: 0, blur: 0))
    }

    @Test @MainActor func terminalGlassAppearanceResolvesOverridesPerDimension() {
        let globalOpacity = 0.25
        let globalBlur = 0.75

        #expect(TerminalGlassAppearance.resolved(
            globalOpacity: globalOpacity,
            globalBlur: globalBlur,
            window: GlassWindowOverrides()
        ) == .init(opacity: 0.25, blur: 0.75))
        #expect(TerminalGlassAppearance.resolved(
            globalOpacity: globalOpacity,
            globalBlur: globalBlur,
            window: TerminalSessionOverride(windowOpacity: 1).windowSettings
        ) == .init(opacity: 1, blur: 0.75))
        #expect(TerminalGlassAppearance.resolved(
            globalOpacity: globalOpacity,
            globalBlur: globalBlur,
            window: TerminalSessionOverride(blurBackground: 0).windowSettings
        ) == .init(opacity: 0.25, blur: 0))
        #expect(TerminalGlassAppearance.resolved(
            globalOpacity: globalOpacity,
            globalBlur: globalBlur,
            window: TerminalSessionOverride(windowOpacity: 0, blurBackground: 1).windowSettings
        ) == .init(opacity: 0, blur: 1))
    }

    @Test @MainActor func appearanceSettingsRoundTripCanonicalGlobalValues() throws {
        let suiteName = "sh.glas.tests.appearance.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(0.91, forKey: UserDefaultsKeys.backgroundFill)
        let settings = SettingsManager(
            loadImmediately: false,
            settingsDefaults: defaults,
            sshKeyDefaults: defaults
        )
        settings.windowOpacity = 0.37
        settings.blurBackground = 0.64
        settings.saveSettings()

        // Opacity and blur are the shared GlassLayers state now; nothing writes the legacy keys.
        let stored = GlassLayerStore(defaults: defaults, legacyDefaults: []).state
        #expect(stored.effectiveOpacity == 0.37)
        #expect(stored.frost == 0.64)
        #expect(defaults.object(forKey: UserDefaultsKeys.windowOpacity) == nil)
        #expect(defaults.object(forKey: UserDefaultsKeys.backgroundFill) == nil)

        let reloaded = SettingsManager(
            settingsDefaults: defaults,
            sshKeyDefaults: defaults
        )
        #expect(reloaded.windowOpacity == 0.37)
        #expect(reloaded.blurBackground == 0.64)
    }

    @Test @MainActor func appearanceMigrationPrefersCanonicalOpacityAndMigratesBooleanOrNumericBlur() throws {
        let booleanSuite = "sh.glas.tests.appearance.boolean.\(UUID().uuidString)"
        let booleanDefaults = try #require(UserDefaults.forTest(suiteName: booleanSuite))
        booleanDefaults.removePersistentDomain(forName: booleanSuite)
        defer { booleanDefaults.removePersistentDomain(forName: booleanSuite) }
        booleanDefaults.set(0.2, forKey: UserDefaultsKeys.windowOpacity)
        booleanDefaults.set(0.9, forKey: UserDefaultsKeys.backgroundFill)
        booleanDefaults.set(true, forKey: UserDefaultsKeys.blurBackground)

        let booleanMigrated = SettingsManager(
            settingsDefaults: booleanDefaults,
            sshKeyDefaults: booleanDefaults
        )
        #expect(booleanMigrated.windowOpacity == 0.2)
        #expect(booleanMigrated.blurBackground == 1)
        #expect(booleanDefaults.object(forKey: UserDefaultsKeys.backgroundFill) == nil)
        #expect(SettingsManager.resolvedBlurBackground(false) == 0)

        let numericSuite = "sh.glas.tests.appearance.numeric.\(UUID().uuidString)"
        let numericDefaults = try #require(UserDefaults.forTest(suiteName: numericSuite))
        numericDefaults.removePersistentDomain(forName: numericSuite)
        defer { numericDefaults.removePersistentDomain(forName: numericSuite) }
        numericDefaults.set(0.42, forKey: UserDefaultsKeys.blurBackground)
        let numericMigrated = SettingsManager(
            settingsDefaults: numericDefaults,
            sshKeyDefaults: numericDefaults
        )
        #expect(numericMigrated.blurBackground == 0.42)
        #expect(SettingsManager.resolvedBlurBackground(-1.0) == 0)
        #expect(SettingsManager.resolvedBlurBackground(2.0) == 1)
        #expect(SettingsManager.resolvedBlurBackground(Double.nan) == 0)
        #expect(SettingsManager.resolvedBlurBackground("maximum") == 0)
    }

    @Test func sessionAppearancePayloadMigratesLegacyBlurAndEncodesOnlyCanonicalKeys() throws {
        let booleanTrue = try JSONDecoder().decode(
            TerminalSessionOverride.self,
            from: Data(#"{"blurBackground":true}"#.utf8)
        )
        let booleanFalse = try JSONDecoder().decode(
            TerminalSessionOverride.self,
            from: Data(#"{"blurBackground":false}"#.utf8)
        )
        let numeric = try JSONDecoder().decode(
            TerminalSessionOverride.self,
            from: Data(#"{"blurBackground":0.42}"#.utf8)
        )
        let canonicalWins = try JSONDecoder().decode(
            TerminalSessionOverride.self,
            from: Data(#"{"windowOpacity":0.2,"backgroundFill":0.9,"blurBackground":2}"#.utf8)
        )

        #expect(booleanTrue.blurBackground == 1)
        #expect(booleanFalse.blurBackground == 0)
        #expect(numeric.blurBackground == 0.42)
        #expect(canonicalWins.windowOpacity == 0.2)
        #expect(canonicalWins.blurBackground == 1)

        let invalid = TerminalSessionOverride(windowOpacity: .nan, blurBackground: -Double.infinity)
        #expect(invalid.windowOpacity == 0)
        #expect(invalid.blurBackground == 0)

        let encoded = try JSONEncoder().encode(canonicalWins)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["windowOpacity"] as? Double == 0.2)
        #expect(object["blurBackground"] as? Double == 1)
        #expect(object["backgroundFill"] == nil)
    }

    @Test func boundedStorageRejectsLimitsAndPreservesHeadroom() throws {
        try BoundedStorage.validateWrite(
            currentBytes: 100,
            incomingBytes: 20,
            maximumBytes: 120,
            availableCapacity: 70,
            headroom: 50
        )

        #expect(throws: BoundedStorageError.sizeLimitExceeded(limit: 119)) {
            try BoundedStorage.validateWrite(
                currentBytes: 100,
                incomingBytes: 20,
                maximumBytes: 119,
                availableCapacity: 1_000,
                headroom: 50
            )
        }

        #expect(throws: BoundedStorageError.insufficientFreeSpace(required: 70, available: 69)) {
            try BoundedStorage.validateWrite(
                currentBytes: 100,
                incomingBytes: 20,
                maximumBytes: 120,
                availableCapacity: 69,
                headroom: 50
            )
        }

        #expect(throws: BoundedStorageError.sizeLimitExceeded(limit: UInt64.max)) {
            try BoundedStorage.validateWrite(
                currentBytes: UInt64.max,
                incomingBytes: 1,
                maximumBytes: UInt64.max,
                availableCapacity: UInt64.max,
                headroom: 0
            )
        }
    }




    @Test @MainActor func socks5CredentialsRemainManagerMemoryOnlyAndLegacyDynamicAddFailsClosed() throws {
        let sessionID = UUID()
        let legacyManager = PortForwardManager()
        let legacyForward = PortForward(type: .dynamic, localPort: 10_80, remotePort: 0)
        legacyManager.addForward(legacyForward, to: sessionID)
        #expect(legacyManager.forwards(for: sessionID).first?.status == .error)
        #expect(legacyManager.configureSOCKS5Credentials(
            for: legacyForward.id,
            username: "proxy-user",
            password: "session-secret"
        ))
        #expect(legacyManager.forwards(for: sessionID).first?.status == .inactive)

        let manager = PortForwardManager()
        let forward = PortForward(type: .dynamic, localPort: 10_81, remotePort: 0)
        #expect(manager.addForward(
            forward,
            to: sessionID,
            socks5Username: "proxy-user",
            socks5Password: "session-secret"
        ))
        let encodedForward = String(decoding: try JSONEncoder().encode(forward), as: UTF8.self)
        #expect(!encodedForward.contains("proxy-user"))
        #expect(!encodedForward.contains("session-secret"))
    }





    // MARK: - TerminalSession Lifecycle Tests

    @Test @MainActor func savedSessionPolicyResolvesCurrentProfileAndFailsClosedAfterDeletion() async throws {
        let original = ServerConfiguration(
            name: "Saved",
            host: "old.example.com",
            username: "user",
            authMethod: .sshKey,
            sshKeyID: UUID()
        )
        let serverManager = ServerManager(loadImmediately: false)
        serverManager.servers = [original]
        let manager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false
        )
        let settings = SettingsManager(loadImmediately: false)
        let session = TerminalSession(server: original)
        manager.registerSession(session)

        var current = original
        current.name = "Current"
        current.host = "current.example.com"
        serverManager.servers = [current]

        let context = try manager.reconnectContext(for: session)
        #expect(context.server == current)
        #expect(context.password == nil)

        serverManager.servers = []

        do {
            _ = try await manager.createAuthorizedSession(
                for: original,
                settingsManager: settings
            )
            Issue.record("A deleted saved profile must not launch from a stale value")
        } catch SessionOpenError.savedServerNotFound {
            // Expected.
        } catch {
            Issue.record("Expected savedServerNotFound, received \(error)")
        }

        do {
            _ = try await manager.duplicateAuthorizedSession(
                from: session,
                settingsManager: settings
            )
            Issue.record("A deleted saved profile must not duplicate from session state")
        } catch SessionOpenError.savedServerNotFound {
            // Expected.
        } catch {
            Issue.record("Expected savedServerNotFound, received \(error)")
        }

        do {
            try await manager.reconnect(session, settingsManager: settings)
            Issue.record("A deleted saved profile must not reconnect from session state")
        } catch SessionOpenError.savedServerNotFound {
            // Expected.
        } catch {
            Issue.record("Expected savedServerNotFound, received \(error)")
        }

        do {
            _ = try await manager.createAuthorizedSessionByServerID(
                original.id,
                settingsManager: settings
            )
            Issue.record("A deleted layout target must not launch")
        } catch SessionOpenError.savedServerNotFound {
            // Expected.
        } catch {
            Issue.record("Expected savedServerNotFound, received \(error)")
        }
    }

    @Test @MainActor func transientSessionPasswordRemainsMemoryBoundUntilUnregister() throws {
        let transient = ServerConfiguration(
            name: "Quick Connect",
            host: "transient.example.com",
            username: "user"
        )
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false
        )
        let session = TerminalSession(server: transient)
        manager.registerTransientSession(session, password: "memory-only-password")

        let reconnect = try manager.reconnectContext(for: session)
        #expect(reconnect.server == transient)
        #expect(reconnect.password == "memory-only-password")

        do {
            _ = try SessionManager.decodeTransientPassword(
                SecureBytes(Data([0xFF, 0xFE]))
            )
            Issue.record("Malformed transient credential bytes must fail closed")
        } catch SessionOpenError.invalidTransientCredentialEncoding {
            // Expected.
        } catch {
            Issue.record("Expected invalidTransientCredentialEncoding, received \(error)")
        }

        manager.closeSession(session)

        do {
            _ = try manager.reconnectContext(for: session)
            Issue.record("Unregister must discard transient reconnect state")
        } catch SessionOpenError.sessionNotRegistered {
            // Expected.
        } catch {
            Issue.record("Expected sessionNotRegistered, received \(error)")
        }
    }

    @Test @MainActor func abandoningPendingHostTrustClosesAndUnregistersInvisibleSession() {
        let server = ServerConfiguration(
            name: "Pending Trust",
            host: "pending.example.com",
            username: "user"
        )
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false
        )
        let session = TerminalSession(server: server)
        session.pendingHostKeyChallenge = HostKeyTrustChallenge(
            host: server.host,
            port: server.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:test-fixture",
            keyDataBase64: Data("test-key".utf8).base64EncodedString(),
            reason: .unknown
        )
        manager.registerTransientSession(session, password: "memory-only-password")

        manager.closePendingHostTrustSession(session)

        #expect(session.pendingHostKeyChallenge == nil)
        #expect(session.state == .disconnected)
        #expect(manager.session(for: session.id) == nil)
    }

    @Test @MainActor func connectionPreparationPreservesDeclaredJumpHostOrder() throws {
        let firstHop = ServerConfiguration(
            name: "First Hop",
            host: "first.example.com",
            username: "first"
        )
        let secondHop = ServerConfiguration(
            name: "Second Hop",
            host: "second.example.com",
            username: "second"
        )
        let target = ServerConfiguration(
            name: "Target",
            host: "target.example.com",
            username: "target",
            jumpHostIDs: [firstHop.id, secondHop.id]
        )
        let serverManager = ServerManager(loadImmediately: false)
        serverManager.servers = [secondHop, target, firstHop]
        var retrievalOrder: [UUID] = []
        let manager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false,
            retrievePassword: { server in
                retrievalOrder.append(server.id)
                return "password"
            }
        )

        let prepared = try manager.prepareConnection(for: target)

        #expect(retrievalOrder == [target.id, firstHop.id, secondHop.id])
        #expect(prepared.jumpHostChain.map(\.id) == [firstHop.id, secondHop.id])
        #expect(prepared.authentication.jumpHosts.map(\.serverID) == [firstHop.id, secondHop.id])
    }

    @Test @MainActor func jumpHostPasswordPreparationDistinguishesMissingFromUnavailable() {
        let hop = ServerConfiguration(
            name: "Jump",
            host: "jump.example.com",
            username: "jump"
        )
        let target = ServerConfiguration(
            name: "Target",
            host: "target.example.com",
            username: "target",
            jumpHostIDs: [hop.id]
        )
        let serverManager = ServerManager(loadImmediately: false)
        serverManager.servers = [target, hop]

        let missingManager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false,
            retrievePassword: { server in
                if server.id == hop.id { throw SecretStoreError.notFound }
                return "target-password"
            }
        )
        do {
            _ = try missingManager.prepareConnection(for: target)
            Issue.record("A missing jump-host password must fail preparation")
        } catch let error as SessionOpenError {
            if case .missingPassword(let server, .jumpHost(1)) = error {
                #expect(server.id == hop.id)
            } else {
                Issue.record("Expected jump-host missingPassword, received \(error)")
            }
        } catch {
            Issue.record("Expected SessionOpenError, received \(error)")
        }

        let unavailableManager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false,
            retrievePassword: { server in
                if server.id == hop.id {
                    throw SecretStoreError.queryFailed(status: -25_308)
                }
                return "target-password"
            }
        )
        do {
            _ = try unavailableManager.prepareConnection(for: target)
            Issue.record("A locked or failed Keychain query must fail preparation")
        } catch let error as SessionOpenError {
            if case .credentialUnavailable(let server, .jumpHost(1)) = error {
                #expect(server.id == hop.id)
            } else {
                Issue.record("Expected jump-host credentialUnavailable, received \(error)")
            }
        } catch {
            Issue.record("Expected SessionOpenError, received \(error)")
        }
    }

    @Test @MainActor func onlyRequestedTargetMissingPasswordRoutesToConnectionPrompt() {
        let requested = ServerConfiguration(
            name: "Requested",
            host: "requested.example.com",
            username: "operator"
        )
        let other = ServerConfiguration(
            name: "Other",
            host: "other.example.com",
            username: "operator"
        )

        let targetError = SessionOpenError.missingPassword(
            server: requested,
            location: .target
        )
        #expect(TerminalConnectFlow.targetPasswordPromptServer(
            for: targetError,
            requestedServerID: requested.id
        )?.id == requested.id)

        #expect(TerminalConnectFlow.targetPasswordPromptServer(
            for: targetError,
            requestedServerID: other.id
        ) == nil)
        #expect(TerminalConnectFlow.targetPasswordPromptServer(
            for: SessionOpenError.missingPassword(server: other, location: .jumpHost(1)),
            requestedServerID: requested.id
        ) == nil)
        #expect(TerminalConnectFlow.targetPasswordPromptServer(
            for: SessionOpenError.credentialUnavailable(server: requested, location: .target),
            requestedServerID: requested.id
        ) == nil)
    }

    @Test @MainActor func connectionManagerIdentifiesLocalNetworkSSHHosts() {
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("localhost"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("nas.local"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("10.20.30.40"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("172.16.0.1"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("172.31.255.255"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("192.168.1.20"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("169.254.1.2"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("127.0.0.1"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("[fe80::1]"))
        #expect(GlassLocalNetworkAccess.isLikelyLocalHost("fd12::20"))

        #expect(!GlassLocalNetworkAccess.isLikelyLocalHost("example.com"))
        #expect(!GlassLocalNetworkAccess.isLikelyLocalHost("172.32.0.1"))
        #expect(!GlassLocalNetworkAccess.isLikelyLocalHost("192.167.1.20"))
        #expect(!GlassLocalNetworkAccess.isLikelyLocalHost("not-an-address"))
    }

    @Test @MainActor func localConnectionFailureAddsActionablePermissionGuidance() {
        let localMessage = TerminalConnectFlow.connectionFailureMessage(
            base: "Could not reach nas.local:22.",
            diagnostics: "Attempted: nas.local:22",
            host: "nas.local",
            mayBeLocalNetworkDenial: true
        )
        #expect(localMessage.contains("Attempted: nas.local:22"))
        #expect(localMessage.contains("Privacy & Security > Local Network"))
        #expect(localMessage.contains("allow Glass Power Tools"))

        let remoteMessage = TerminalConnectFlow.connectionFailureMessage(
            base: "Could not reach example.com:22.",
            diagnostics: nil,
            host: "example.com",
            mayBeLocalNetworkDenial: true
        )
        #expect(!remoteMessage.contains("Local Network"))
    }

    /// B-X13 (2026-10-13): the guidance was added to any failure on a local-looking host. Only a
    /// failure the system's denial could cause gets it — measured, "No route to host" (errno 65).
    @Test @MainActor func localNetworkGuidanceOnlyWhereTheDenialCouldBeTheCause() {
        let noRoute = IOError(errnoCode: EHOSTUNREACH, reason: "connect(descriptor:addr:size:)")
        #expect(GlassLocalNetworkAccess.mayBeDenial(noRoute))
        #expect(GlassLocalNetworkAccess.mayBeDenial(NSError(domain: NSPOSIXErrorDomain, code: Int(EHOSTUNREACH))))
        #expect(GlassLocalNetworkAccess.mayBeDenial(NSError(domain: "DNSServiceErrorDomain", code: -65_570)))
        #expect(!GlassLocalNetworkAccess.mayBeDenial(IOError(errnoCode: ECONNREFUSED, reason: "connect")))
        #expect(!GlassLocalNetworkAccess.mayBeDenial(ChannelError.connectTimeout(.seconds(10))))
        #expect(!GlassLocalNetworkAccess.mayBeDenial(SSHError.authenticationFailed))

        for (base, diagnostics) in [("Connection refused by nas.local:22. Verify SSH is running on that port.", nil),
                                    ("Connection to nas.local:22 timed out.", nil),
                                    ("Authentication failed for me@nas.local:22.", "Auth method: Password")] {
            let message = TerminalConnectFlow.connectionFailureMessage(
                base: base, diagnostics: diagnostics, host: "nas.local", mayBeLocalNetworkDenial: false)
            #expect(!message.contains("Local Network"), "\(base)")
        }
    }

    #if os(macOS)
    #endif

    @Test @MainActor func initialLaunchPreparesEveryCredentialBeforeSessionRegistration() async {
        let hop = ServerConfiguration(
            name: "Jump",
            host: "jump.example.com",
            username: "jump"
        )
        let target = ServerConfiguration(
            name: "Target",
            host: "target.example.com",
            username: "target",
            jumpHostIDs: [hop.id]
        )
        let serverManager = ServerManager(loadImmediately: false)
        serverManager.servers = [target, hop]
        let manager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false,
            retrievePassword: { server in
                if server.id == hop.id { throw SecretStoreError.notFound }
                return "target-password"
            }
        )

        do {
            _ = try await manager.createAuthorizedSession(
                for: target,
                settingsManager: SettingsManager(loadImmediately: false)
            )
            Issue.record("Initial launch must prepare the full jump chain before connecting")
        } catch let error as SessionOpenError {
            if case .missingPassword(let server, .jumpHost(1)) = error {
                #expect(server.id == hop.id)
            } else {
                Issue.record("Expected jump-host missingPassword, received \(error)")
            }
        } catch {
            Issue.record("Expected SessionOpenError, received \(error)")
        }

        #expect(manager.sessions.isEmpty)
    }

    @Test @MainActor func reconnectPreparationRefreshesCurrentJumpHostAndFailsAfterDeletion() throws {
        let originalHop = ServerConfiguration(
            name: "Jump",
            host: "old-jump.example.com",
            username: "jump"
        )
        let target = ServerConfiguration(
            name: "Target",
            host: "target.example.com",
            username: "target",
            jumpHostIDs: [originalHop.id]
        )
        let serverManager = ServerManager(loadImmediately: false)
        serverManager.servers = [target, originalHop]
        let manager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false,
            retrievePassword: { _ in "password" }
        )
        let session = TerminalSession(server: target)
        manager.registerSession(session)

        var currentHop = originalHop
        currentHop.host = "current-jump.example.com"
        serverManager.servers = [target, currentHop]

        let context = try manager.reconnectContext(for: session)
        let refreshed = try manager.prepareConnection(for: context.server)
        #expect(refreshed.jumpHostChain == [currentHop])

        serverManager.servers = [target]
        do {
            _ = try manager.prepareConnection(for: context.server)
            Issue.record("Deleting a current jump host must block reconnect preparation")
        } catch SessionOpenError.jumpHostNotFound {
            // Expected.
        } catch {
            Issue.record("Expected jumpHostNotFound, received \(error)")
        }
    }

    @Test @MainActor func manualReconnectCancelsAutomaticReconnectBeforeCredentialQuery() async {
        let target = ServerConfiguration(
            name: "Target",
            host: "target.example.com",
            username: "target"
        )
        let session = TerminalSession(server: target)
        var stateObservedDuringQuery: SessionState?
        let serverManager = ServerManager(loadImmediately: false)
        serverManager.servers = [target]
        let manager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false,
            retrievePassword: { _ in
                stateObservedDuringQuery = session.state
                throw SecretStoreError.queryFailed(status: -25_308)
            }
        )
        manager.registerSession(session)
        session.state = .reconnecting

        do {
            try await manager.reconnect(
                session,
                settingsManager: SettingsManager(loadImmediately: false)
            )
            Issue.record("Credential query failure must block reconnect")
        } catch let error as SessionOpenError {
            if case .credentialUnavailable(let server, .target) = error {
                #expect(server.id == target.id)
            } else {
                Issue.record("Expected target credentialUnavailable, received \(error)")
            }
        } catch {
            Issue.record("Expected SessionOpenError, received \(error)")
        }

        #expect(stateObservedDuringQuery == .disconnected)
    }

    @Test @MainActor func corruptSSHKeyMaterialMapsToTypedSessionError() {
        let keyID = UUID()
        let target = ServerConfiguration(
            name: "Key Target",
            host: "key.example.com",
            username: "target",
            authMethod: .sshKey,
            sshKeyID: keyID
        )
        let serverManager = ServerManager(loadImmediately: false)
        serverManager.servers = [target]
        let manager = SessionManager(
            serverManager: serverManager,
            loadImmediately: false,
            retrieveSSHKey: { _ in
                SSHKeyMaterial(
                    privateKey: SecureBytes(Data([0xFF, 0xFE])),
                    passphrase: nil
                )
            }
        )

        do {
            _ = try manager.prepareConnection(for: target)
            Issue.record("Corrupt SSH key bytes must fail preparation")
        } catch let error as SessionOpenError {
            if case .invalidSSHKey(let server, .target) = error {
                #expect(server.id == target.id)
            } else {
                Issue.record("Expected target invalidSSHKey, received \(error)")
            }
        } catch {
            Issue.record("Expected SessionOpenError, received \(error)")
        }
    }

    @Test @MainActor func sessionManagerLifecycleHookStopsForwardsOnceBeforeEveryDetachTransition() {
        let detachingTransitions: [TerminalSessionLifecycleTransition] = [
            .manualReconnect,
            .automaticReconnect,
            .explicitDisconnect,
            .cleanRemoteExit,
        ]

        for transition in detachingTransitions {
            let session = TerminalSession(server: ServerConfiguration(
                name: "Lifecycle",
                host: "example.com",
                username: "user"
            ))
            var stoppedSessionIDs: [UUID] = []
            var hookObservedAttachedConnection = false
            let manager = SessionManager(
                serverManager: ServerManager(loadImmediately: false),
                loadImmediately: false,
                stopSessionForwards: { sessionID in
                    hookObservedAttachedConnection = session.getSSHConnection() != nil
                    stoppedSessionIDs.append(sessionID)
                }
            )
            manager.registerSession(session)

            _ = session.detachSSHConnection(for: transition)
            _ = session.detachSSHConnection(for: transition)

            #expect(hookObservedAttachedConnection)
            #expect(stoppedSessionIDs == [session.id])
            #expect(session.getSSHConnection() == nil)
        }
    }

    @Test @MainActor func sessionManagerLifecycleHookStopsForwardsOnceForTerminalError() {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Lifecycle",
            host: "example.com",
            username: "user"
        ))
        var stoppedSessionIDs: [UUID] = []
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false,
            stopSessionForwards: { stoppedSessionIDs.append($0) }
        )
        manager.registerSession(session)

        session.reportError("transport failed")
        session.reportError("duplicate transport callback")

        #expect(stoppedSessionIDs == [session.id])
        #expect(session.state == .error("duplicate transport callback"))
        #expect(session.getSSHConnection() == nil)
    }

    @Test @MainActor func closeSessionUsesLifecycleHookAndPreservesUnregisterBehavior() {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Lifecycle",
            host: "example.com",
            username: "user"
        ))
        var stoppedSessionIDs: [UUID] = []
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false,
            stopSessionForwards: { stoppedSessionIDs.append($0) }
        )
        manager.registerSession(session)

        manager.closeSession(session)

        #expect(stoppedSessionIDs == [session.id])
        #expect(session.state == .disconnected)
        #expect(manager.session(for: session.id) == nil)
    }

    @Test @MainActor func closeSessionPurgesSOCKS5CredentialsAfterAwaitedForwardShutdown() async {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Lifecycle",
            host: "example.com",
            username: "user"
        ))
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false
        )
        manager.registerSession(session)
        let forward = PortForward(type: .dynamic, localPort: 10_82, remotePort: 0)
        #expect(manager.portForwardManager.addForward(
            forward,
            to: session.id,
            socks5Username: "proxy-user",
            socks5Password: "session-secret"
        ))
        #expect(manager.portForwardManager.hasSOCKS5Credentials(for: forward.id))

        manager.closeSession(session)
        await session.awaitLifecycleCleanup()
        for _ in 0..<10 where !manager.portForwardManager.forwards(for: session.id).isEmpty {
            await Task.yield()
        }

        #expect(manager.portForwardManager.forwards(for: session.id).isEmpty)
        #expect(!manager.portForwardManager.hasSOCKS5Credentials(for: forward.id))
    }

    @Test @MainActor func reconnectShutdownRetainsForwardRowsAndSOCKS5Credentials() async {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Lifecycle",
            host: "example.com",
            username: "user"
        ))
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false
        )
        manager.registerSession(session)
        let forward = PortForward(type: .dynamic, localPort: 10_83, remotePort: 0)
        #expect(manager.portForwardManager.addForward(
            forward,
            to: session.id,
            socks5Username: "proxy-user",
            socks5Password: "session-secret"
        ))

        _ = session.detachSSHConnection(for: .manualReconnect)
        await session.awaitLifecycleCleanup()

        #expect(manager.session(for: session.id) === session)
        #expect(manager.portForwardManager.forwards(for: session.id).map(\.id) == [forward.id])
        #expect(manager.portForwardManager.hasSOCKS5Credentials(for: forward.id))
    }

    @Test @MainActor func unregisterPurgeDoesNotRaceSessionReregistration() async {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Lifecycle",
            host: "example.com",
            username: "user"
        ))
        let manager = SessionManager(
            serverManager: ServerManager(loadImmediately: false),
            loadImmediately: false
        )
        manager.registerSession(session)
        let forward = PortForward(type: .dynamic, localPort: 10_84, remotePort: 0)
        #expect(manager.portForwardManager.addForward(
            forward,
            to: session.id,
            socks5Username: "proxy-user",
            socks5Password: "session-secret"
        ))

        manager.closeSession(session)
        manager.registerSession(session)
        await session.awaitLifecycleCleanup()
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(manager.session(for: session.id) === session)
        #expect(manager.portForwardManager.forwards(for: session.id).map(\.id) == [forward.id])
        #expect(manager.portForwardManager.hasSOCKS5Credentials(for: forward.id))
    }

    @Test @MainActor func terminalSessionInitialState() {
        let server = ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        )
        let session = TerminalSession(server: server)

        #expect(session.state == .disconnected)
        #expect(session.output.isEmpty)
        #expect(session.pendingHostKeyChallenge == nil)
        #expect(session.connectionProgress == nil)
        #expect(session.server.host == "example.com")
    }

    @Test @MainActor func terminalSessionRetainsOneRendererHostIdentity() {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        ))

        let initialHost = session.terminalHostModel
        #expect(initialHost === session.terminalHostModel)
    }

    @Test @MainActor func terminalSessionDisconnect() {
        let server = ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        )
        let session = TerminalSession(server: server)
        session.disconnect()

        #expect(session.state == .disconnected)
        #expect(session.connectionProgress == nil)
    }

    @Test @MainActor func terminalSessionCleanRemoteExit() {
        let server = ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        )
        let session = TerminalSession(server: server)
        let initialNonce = session.closeWindowNonce

        session.feedTerminalData(Data("final remote bytes".utf8))

        session.handleCleanRemoteExit()

        #expect(session.state == .disconnected)
        #expect(session.connectionProgress == nil)
        #expect(session.closeWindowNonce == initialNonce &+ 1)
        #expect(
            session.terminalHostModel.pendingRendererByteCount
                == Data("final remote bytes".utf8).count
        )
    }

    @Test @MainActor func terminalSessionClearPreservesBufferedOutputBeforeClearSequence() {
        let session = TerminalSession(server: ServerConfiguration(
            name: "Test",
            host: "example.com",
            port: 22,
            username: "user"
        ))

        session.feedTerminalData(Data("tail".utf8))
        session.clearScreen()

        #expect(session.terminalInputNonce == 2)
        #expect(
            session.terminalHostModel.pendingRendererByteCount
                == Data("tail\u{1B}[2J\u{1B}[H".utf8).count
        )
    }

    @Test @MainActor func terminalSessionSerializesMixedOutboundWrites() async {
        let probe = TerminalWriteProbe()
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Test",
                host: "example.com",
                port: 22,
                username: "user"
            ),
            terminalWriteSink: { data in
                try await probe.receive(data)
            }
        )
        session.state = .connected

        session.sendTerminalData(Data("first".utf8))
        session.sendCommand("second")
        session.sendTerminalData(Data("third".utf8))
        await session.waitUntilTerminalWritesComplete()

        #expect(probe.writes == [
            Data("first".utf8),
            Data("second\n".utf8),
            Data("third".utf8),
        ])
    }

    @Test @MainActor func terminalSessionRejectsInputOutsideConnectedState() async {
        let probe = TerminalWriteProbe()
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Test",
                host: "example.com",
                port: 22,
                username: "user"
            ),
            terminalWriteSink: { data in
                try await probe.receive(data)
            }
        )

        session.state = .reconnecting
        session.sendTerminalData(Data("not sent".utf8))
        session.sendCommand("also not sent")
        await session.waitUntilTerminalWritesComplete()

        #expect(probe.writes.isEmpty)
        #expect(session.output.last?.text == "Error: terminal is not connected.")
    }

    @Test @MainActor func terminalSessionSurfacesFailureWhenDiscardedQueueContainsCommand() async {
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Test",
                host: "example.com",
                port: 22,
                username: "user"
            ),
            terminalWriteSink: { _ in throw TerminalWriteFailure() }
        )
        session.state = .connected

        session.sendTerminalData(Data("raw".utf8))
        session.sendCommand("visible command")
        await session.waitUntilTerminalWritesComplete()

        #expect(session.output.contains { $0.text.hasPrefix("Error:") })
    }

    @Test @MainActor func terminalStartupCommandDispatchesOnlyOnFirstConnectedTransition() async {
        let probe = TerminalWriteProbe()
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Test",
                host: "example.com",
                port: 22,
                username: "user"
            ),
            terminalWriteSink: { data in try await probe.receive(data) }
        )

        #expect(session.installStartupCommand("htop"))
        #expect(session.hasPendingStartupCommand)
        session.state = .connected
        await session.waitUntilTerminalWritesComplete()
        session.state = .reconnecting
        session.state = .connected
        await session.waitUntilTerminalWritesComplete()

        #expect(probe.writes == [Data("htop\n".utf8)])
        #expect(!session.hasPendingStartupCommand)
    }

    @Test @MainActor func terminalStartupCommandFailureNeverReplaysOnReconnect() async {
        var writeCount = 0
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Test",
                host: "example.com",
                port: 22,
                username: "user"
            ),
            terminalWriteSink: { _ in
                writeCount += 1
                throw TerminalWriteFailure()
            }
        )

        #expect(session.installStartupCommand("deploy"))
        session.state = .connected
        await session.waitUntilTerminalWritesComplete()
        session.state = .reconnecting
        session.state = .connected
        await session.waitUntilTerminalWritesComplete()

        #expect(writeCount == 1)
        #expect(!session.hasPendingStartupCommand)
    }

    @Test @MainActor func runtimeWorkgroupsKeepWindowsAndSessionsIsolated() {
        let manager = SessionManager(loadImmediately: false)
        let first = TerminalSession(server: ServerConfiguration(
            name: "First", host: "first.example.com", port: 22, username: "user"
        ))
        let second = TerminalSession(server: ServerConfiguration(
            name: "Second", host: "second.example.com", port: 22, username: "user"
        ))
        let third = TerminalSession(server: ServerConfiguration(
            name: "Third", host: "third.example.com", port: 22, username: "user"
        ))
        manager.registerSession(first)
        manager.registerSession(second)
        manager.registerSession(third)
        let firstGroup = manager.createWorkgroup(name: "One", colorTag: .red)
        let secondGroup = manager.createWorkgroup(name: "Two", colorTag: .cyan)

        #expect(manager.appendSession(first, toWorkgroup: firstGroup))
        #expect(manager.appendSession(second, toWorkgroup: secondGroup))
        #expect(manager.appendSession(third, toWorkgroup: secondGroup))
        #expect(!manager.appendSession(first, toWorkgroup: secondGroup))
        #expect(manager.workgroup(for: secondGroup)?.selectedSessionID == third.id)

        manager.removeSessionFromWorkgroup(third)

        #expect(manager.workgroup(for: secondGroup)?.sessionIDs == [second.id])
        #expect(manager.workgroup(for: secondGroup)?.selectedSessionID == second.id)
        #expect(manager.session(for: third.id) == nil)

        manager.closeWorkgroup(firstGroup)

        #expect(manager.workgroup(for: firstGroup) == nil)
        #expect(manager.session(for: first.id) == nil)
        #expect(manager.workgroup(for: secondGroup)?.sessionIDs == [second.id])
        #expect(manager.session(for: second.id) === second)
    }

    @Test @MainActor func runtimeWorkgroupOrderingAndSelectionAreModelAuthoritative() {
        let manager = SessionManager(loadImmediately: false)
        let first = TerminalSession(server: ServerConfiguration(
            name: "First", host: "first.example.com", port: 22, username: "user"
        ))
        let second = TerminalSession(server: ServerConfiguration(
            name: "Second", host: "second.example.com", port: 22, username: "user"
        ))
        let third = TerminalSession(server: ServerConfiguration(
            name: "Third", host: "third.example.com", port: 22, username: "user"
        ))
        for session in [first, second, third] {
            manager.registerSession(session)
        }
        let workgroupID = manager.createWorkgroup(name: "Ordered", colorTag: .blue)
        #expect(manager.appendSession(first, toWorkgroup: workgroupID))
        #expect(manager.appendSession(second, toWorkgroup: workgroupID))
        #expect(manager.appendSession(third, toWorkgroup: workgroupID))

        #expect(manager.sessions(inWorkgroup: workgroupID).map(\.id) == [
            first.id,
            second.id,
            third.id,
        ])
        #expect(manager.selectedSession(inWorkgroup: workgroupID) === third)
        #expect(manager.selectSession(first.id, inWorkgroup: workgroupID))
        #expect(!manager.selectSession(UUID(), inWorkgroup: workgroupID))

        #expect(manager.moveSession(first.id, inWorkgroup: workgroupID, to: 2))
        #expect(manager.sessions(inWorkgroup: workgroupID).map(\.id) == [
            second.id,
            third.id,
            first.id,
        ])
        #expect(manager.selectedSession(inWorkgroup: workgroupID) === first)
        #expect(manager.moveSession(third.id, inWorkgroup: workgroupID, to: 0))
        #expect(manager.sessions(inWorkgroup: workgroupID).map(\.id) == [
            third.id,
            second.id,
            first.id,
        ])
        #expect(manager.selectedSession(inWorkgroup: workgroupID) === first)
        #expect(!manager.moveSession(first.id, inWorkgroup: workgroupID, to: 3))
        #expect(!manager.moveSession(UUID(), inWorkgroup: workgroupID, to: 0))
    }

    @Test @MainActor func detachedTabsRepairSelectionAndRetainLiveAuthority() {
        let manager = SessionManager(loadImmediately: false)
        let first = TerminalSession(server: ServerConfiguration(
            name: "First", host: "first.example.com", port: 22, username: "user"
        ))
        let second = TerminalSession(server: ServerConfiguration(
            name: "Second", host: "second.example.com", port: 22, username: "user"
        ))
        let third = TerminalSession(server: ServerConfiguration(
            name: "Third", host: "third.example.com", port: 22, username: "user"
        ))
        for session in [first, second, third] {
            manager.registerSession(session)
        }
        let workgroupID = manager.createWorkgroup(name: "Transfer Source", colorTag: .purple)
        #expect(manager.appendSession(first, toWorkgroup: workgroupID))
        #expect(manager.appendSession(second, toWorkgroup: workgroupID))
        #expect(manager.appendSession(third, toWorkgroup: workgroupID))
        #expect(manager.selectSession(second.id, inWorkgroup: workgroupID))

        #expect(manager.detachSession(second.id, fromWorkgroup: workgroupID))
        #expect(manager.workgroup(for: workgroupID)?.sessionIDs == [first.id, third.id])
        #expect(manager.workgroup(for: workgroupID)?.selectedSessionID == third.id)
        #expect(manager.selectedSession(inWorkgroup: workgroupID) === third)
        #expect(manager.session(for: second.id) === second)

        #expect(manager.detachSession(third.id, fromWorkgroup: workgroupID))
        #expect(manager.workgroup(for: workgroupID)?.sessionIDs == [first.id])
        #expect(manager.selectedSession(inWorkgroup: workgroupID) === first)
        #expect(manager.detachSession(first.id, fromWorkgroup: workgroupID))

        #expect(manager.workgroup(for: workgroupID)?.sessionIDs == [])
        #expect(manager.workgroup(for: workgroupID)?.selectedSessionID == nil)
        #expect(manager.sessions.map(\.id) == [first.id, second.id, third.id])
        #expect([first, second, third].allSatisfy { $0.state == .disconnected })

        manager.discardWorkgroupIfEmpty(workgroupID)
        #expect(manager.workgroup(for: workgroupID) == nil)
        #expect(manager.sessions.map(\.id) == [first.id, second.id, third.id])
    }

    @Test @MainActor func workgroupTransferCommitsMembershipAndSelectionTogether() {
        let manager = SessionManager(loadImmediately: false)
        let first = TerminalSession(server: ServerConfiguration(
            name: "First", host: "first.example.com", port: 22, username: "user"
        ))
        let second = TerminalSession(server: ServerConfiguration(
            name: "Second", host: "second.example.com", port: 22, username: "user"
        ))
        let destinationSession = TerminalSession(server: ServerConfiguration(
            name: "Destination",
            host: "destination.example.com",
            port: 22,
            username: "user"
        ))
        for session in [first, second, destinationSession] {
            manager.registerSession(session)
        }
        let sourceID = manager.createWorkgroup(name: "Source", colorTag: .purple)
        let destinationID = manager.createWorkgroup(name: "Destination", colorTag: .cyan)
        #expect(manager.appendSession(first, toWorkgroup: sourceID))
        #expect(manager.appendSession(second, toWorkgroup: sourceID))
        #expect(manager.appendSession(destinationSession, toWorkgroup: destinationID))
        #expect(manager.selectSession(first.id, inWorkgroup: sourceID))

        #expect(manager.transferSession(
            first.id,
            fromWorkgroup: sourceID,
            toWorkgroup: destinationID,
            at: 0
        ))

        #expect(manager.workgroup(for: sourceID)?.sessionIDs == [second.id])
        #expect(manager.selectedSession(inWorkgroup: sourceID) === second)
        #expect(manager.workgroup(for: destinationID)?.sessionIDs == [
            first.id,
            destinationSession.id,
        ])
        #expect(manager.selectedSession(inWorkgroup: destinationID) === first)
        #expect(manager.session(for: first.id) === first)
    }

    @Test @MainActor func rejectedWorkgroupTransfersLeaveBothGroupsUnchanged() {
        let manager = SessionManager(loadImmediately: false)
        let sourceSession = TerminalSession(server: ServerConfiguration(
            name: "Source", host: "source.example.com", port: 22, username: "user"
        ))
        let ungroupedSession = TerminalSession(server: ServerConfiguration(
            name: "Ungrouped", host: "ungrouped.example.com", port: 22, username: "user"
        ))
        manager.registerSession(sourceSession)
        manager.registerSession(ungroupedSession)
        let sourceID = manager.createWorkgroup(name: "Source", colorTag: .purple)
        let destinationID = manager.createWorkgroup(name: "Destination", colorTag: .cyan)
        #expect(manager.appendSession(sourceSession, toWorkgroup: sourceID))

        let initialWorkgroups = manager.workgroups
        #expect(!manager.transferSession(
            UUID(),
            fromWorkgroup: sourceID,
            toWorkgroup: destinationID,
            at: 0
        ))
        #expect(!manager.transferSession(
            ungroupedSession.id,
            fromWorkgroup: sourceID,
            toWorkgroup: destinationID,
            at: 0
        ))
        #expect(!manager.transferSession(
            sourceSession.id,
            fromWorkgroup: sourceID,
            toWorkgroup: UUID(),
            at: 0
        ))
        #expect(!manager.transferSession(
            sourceSession.id,
            fromWorkgroup: sourceID,
            toWorkgroup: destinationID,
            at: 1
        ))
        #expect(!manager.transferSession(
            sourceSession.id,
            fromWorkgroup: sourceID,
            toWorkgroup: sourceID,
            at: 0
        ))
        #expect(manager.workgroups == initialWorkgroups)

        for index in 0..<LayoutPreset.maximumSessionCount {
            let session = TerminalSession(server: ServerConfiguration(
                name: "Destination \(index)",
                host: "destination-\(index).example.com",
                port: 22,
                username: "user"
            ))
            manager.registerSession(session)
            #expect(manager.appendSession(session, toWorkgroup: destinationID))
        }
        let fullDestinationWorkgroups = manager.workgroups
        #expect(!manager.transferSession(
            sourceSession.id,
            fromWorkgroup: sourceID,
            toWorkgroup: destinationID,
            at: 0
        ))
        #expect(manager.workgroups == fullDestinationWorkgroups)
        #expect(manager.session(for: sourceSession.id) === sourceSession)
    }

    @Test @MainActor func explicitTabCloseRepairsSelectionAndOwnsDisconnection() {
        let manager = SessionManager(loadImmediately: false)
        let first = TerminalSession(server: ServerConfiguration(
            name: "First", host: "first.example.com", port: 22, username: "user"
        ))
        let second = TerminalSession(server: ServerConfiguration(
            name: "Second", host: "second.example.com", port: 22, username: "user"
        ))
        let third = TerminalSession(server: ServerConfiguration(
            name: "Third", host: "third.example.com", port: 22, username: "user"
        ))
        for session in [first, second, third] {
            manager.registerSession(session)
        }
        let workgroupID = manager.createWorkgroup(name: "Explicit Close", colorTag: .orange)
        #expect(manager.appendSession(first, toWorkgroup: workgroupID))
        #expect(manager.appendSession(second, toWorkgroup: workgroupID))
        #expect(manager.appendSession(third, toWorkgroup: workgroupID))
        #expect(manager.selectSession(second.id, inWorkgroup: workgroupID))

        #expect(manager.closeSession(second.id, inWorkgroup: workgroupID))
        #expect(manager.workgroup(for: workgroupID)?.sessionIDs == [first.id, third.id])
        #expect(manager.selectedSession(inWorkgroup: workgroupID) === third)
        #expect(manager.session(for: second.id) == nil)
        #expect(second.state == .disconnected)

        #expect(manager.closeSession(third.id, inWorkgroup: workgroupID))
        #expect(manager.workgroup(for: workgroupID)?.sessionIDs == [first.id])
        #expect(manager.selectedSession(inWorkgroup: workgroupID) === first)
        #expect(manager.closeSession(first.id, inWorkgroup: workgroupID))
        #expect(manager.workgroup(for: workgroupID) == nil)
        #expect(manager.sessions.isEmpty)
        #expect(!manager.closeSession(first.id, inWorkgroup: workgroupID))
    }

    #if os(iOS)
    @Test @MainActor func iOSRoutersKeepSceneNavigationIndependent() {
        let first = IOSAppRouter()
        let second = IOSAppRouter()
        let workgroupID = UUID()

        first.showTerminal(workgroupID: workgroupID)
        first.showSFTP(sessionID: UUID())

        #expect(first.terminalWorkgroupID == workgroupID)
        #expect(first.sftpContext != nil)
        #expect(second.terminalWorkgroupID == nil)
        #expect(second.sftpContext == nil)
    }

    @Test @MainActor func iOSRouterResumesExactLiveWorkgroupWithDuplicateServerSessions() {
        let manager = SessionManager(loadImmediately: false)
        let sharedServer = ServerConfiguration(
            name: "Shared",
            host: "shared.example.com",
            port: 22,
            username: "user"
        )
        let first = TerminalSession(server: sharedServer)
        let second = TerminalSession(server: sharedServer)
        manager.registerSession(first)
        manager.registerSession(second)
        let firstGroup = manager.createWorkgroup(name: "First Group", colorTag: .red)
        let secondGroup = manager.createWorkgroup(name: "Second Group", colorTag: .cyan)
        #expect(manager.appendSession(first, toWorkgroup: firstGroup))
        #expect(manager.appendSession(second, toWorkgroup: secondGroup))

        let router = IOSAppRouter()
        router.showTerminal(workgroupID: secondGroup)
        router.showConnections()

        #expect(router.terminalWorkgroupID == nil)
        #expect(router.mostRecentTerminalWorkgroupID == secondGroup)
        #expect(router.liveWorkgroups(in: manager).map(\.id) == [firstGroup, secondGroup])
        #expect(router.resumeMostRecentTerminal(in: manager))
        #expect(router.terminalWorkgroupID == secondGroup)
        #expect(manager.workgroup(for: secondGroup)?.selectedSessionID == second.id)

        router.showConnections()
        #expect(router.resumeTerminal(workgroupID: firstGroup, in: manager))
        #expect(router.terminalWorkgroupID == firstGroup)
        #expect(manager.workgroup(for: firstGroup)?.selectedSessionID == first.id)

        router.showTerminal(workgroupID: secondGroup)
        router.showConnections()
        manager.closeWorkgroup(secondGroup)

        #expect(router.resumableWorkgroupID(in: manager) == firstGroup)
        #expect(!router.resumeTerminal(workgroupID: secondGroup, in: manager))
        #expect(router.resumeMostRecentTerminal(in: manager))
        #expect(router.terminalWorkgroupID == firstGroup)
    }

    @Test @MainActor func iOSRouterKeepsTransientOnlyWorkgroupReachable() {
        let manager = SessionManager(loadImmediately: false)
        let transientServer = ServerConfiguration(
            name: "Quick Connect",
            host: "transient.example.com",
            port: 22,
            username: "temporary"
        )
        let transientSession = TerminalSession(server: transientServer)
        manager.registerTransientSession(transientSession, password: "memory-only-password")
        let workgroupID = manager.createWorkgroup(
            name: "Transient Group",
            colorTag: .purple
        )
        #expect(manager.appendSession(transientSession, toWorkgroup: workgroupID))
        #expect(manager.serverManager.server(for: transientServer.id) == nil)

        let router = IOSAppRouter()
        router.showTerminal(workgroupID: workgroupID)
        router.showConnections()

        #expect(router.liveWorkgroups(in: manager).map(\.id) == [workgroupID])
        #expect(router.resumeMostRecentTerminal(in: manager))
        #expect(router.terminalWorkgroupID == workgroupID)
        #expect(manager.workgroup(for: workgroupID)?.selectedSessionID == transientSession.id)

        router.showConnections()
        manager.closeWorkgroup(workgroupID)
        #expect(router.resumableWorkgroupID(in: manager) == nil)
        #expect(!router.resumeMostRecentTerminal(in: manager))
    }
    #endif

    @Test @MainActor func terminalSessionCoalescesRapidRemotePTYResizes() async {
        let probe = TerminalResizeProbe()
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Test",
                host: "example.com",
                port: 22,
                username: "user"
            ),
            terminalResizeSink: { rows, columns in
                try await probe.receive(rows: rows, columns: columns)
            }
        )
        session.state = .connected

        session.updateTerminalGeometry(rows: 24, columns: 80)
        while probe.resizes.isEmpty {
            await Task.yield()
        }
        session.updateTerminalGeometry(rows: 30, columns: 100)
        session.updateTerminalGeometry(rows: 40, columns: 120)
        await session.waitUntilTerminalResizesComplete()

        #expect(probe.resizes == ["24x80", "40x120"])
    }

    @Test @MainActor func terminalGeometryDefaultsPersistAndConnectionOverrideWins() throws {
        let suiteName = "sh.glas.tests.terminal-geometry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = SettingsManager(
            loadImmediately: false,
            settingsDefaults: defaults,
            sshKeyDefaults: defaults
        )
        #expect(initial.initialTerminalColumns == 120)
        #expect(initial.initialTerminalRows == 40)

        initial.initialTerminalColumns = 164
        initial.initialTerminalRows = 52
        initial.saveSettings()

        let reloaded = SettingsManager(
            settingsDefaults: defaults,
            sshKeyDefaults: defaults
        )
        let inherited = ServerConfiguration(
            name: "Inherited",
            host: "inherited.example.com",
            username: "user"
        )
        let overridden = ServerConfiguration(
            name: "Overridden",
            host: "overridden.example.com",
            username: "user",
            initialTerminalColumns: 98,
            initialTerminalRows: 31
        )

        #expect(reloaded.initialTerminalGeometry(for: inherited)
            == TerminalGeometry(rows: 52, columns: 164))
        #expect(reloaded.initialTerminalGeometry(for: overridden)
            == TerminalGeometry(rows: 31, columns: 98))
    }

    @Test @MainActor func initialTerminalPresentationUsesFirstMeasuredGeometry() async {
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Measured",
                host: "measured.example.com",
                username: "user"
            ),
            initialTerminalGeometry: TerminalGeometry(rows: 40, columns: 120)
        )
        session.installInitialTerminalPresentationRequest { pendingSession in
            pendingSession.updateTerminalGeometry(rows: 47, columns: 153)
        }

        let measured = await session.prepareInitialTerminalPresentation(
            timeout: .milliseconds(50)
        )

        #expect(measured)
        #expect(session.didRequestInitialTerminalPresentation)
        #expect(session.hasMeasuredTerminalGeometry)
        #expect(session.currentTerminalGeometry == TerminalGeometry(rows: 47, columns: 153))
    }

    @Test @MainActor func initialTerminalPresentationTimesOutToConfiguredFallback() async {
        let fallback = TerminalGeometry(rows: 55, columns: 175)
        let session = TerminalSession(
            server: ServerConfiguration(
                name: "Background",
                host: "background.example.com",
                username: "user"
            ),
            initialTerminalGeometry: fallback
        )
        session.installInitialTerminalPresentationRequest { _ in }

        let measured = await session.prepareInitialTerminalPresentation(
            timeout: .milliseconds(10)
        )

        #expect(!measured)
        #expect(session.didRequestInitialTerminalPresentation)
        #expect(!session.hasMeasuredTerminalGeometry)
        #expect(session.currentTerminalGeometry == fallback)
    }

    // MARK: - SSH Config Parser Edge Cases

    @Test func sshConfigMatchCannotOverwritePreviousHost() {
        let (entries, warnings) = SSHConfigParser.parse("""
        Host production
          HostName prod.example.com
          User deploy
        Match host staging
          HostName staging.example.com
          User root
          Port 2222
        Match all
          IdentityFile ~/.ssh/conditional
        Host development
          User developer
        """)
        #expect(entries.count == 2)
        #expect(entries[0].hostName == "prod.example.com")
        #expect(entries[0].user == "deploy")
        #expect(entries[0].port == nil)
        #expect(entries[0].identityFile == nil)
        #expect(entries[1].user == "developer")
        #expect(warnings.filter { $0.contains("Match block") }.count == 2)
    }

    @Test func sshConfigMalformedScopeDeclarationsDoNotLeak() {
        let (entries, warnings) = SSHConfigParser.parse("""
        Host first
          User original
        Match
          User conditional
        Host second
          User second
        Host
          HostName stray.example.com
        """)
        #expect(entries.count == 2)
        #expect(entries[0].user == "original")
        #expect(entries[1].hostName == nil)
        #expect(!warnings.isEmpty)
    }

    @Test func sshConfigParsesEqualsAndQuotedValues() {
        let (entries, warnings) = SSHConfigParser.parse("""
        Host=dev
          HostName = "dev.example.com"
          User="developer"
          IdentityFile "~/.ssh/key #1" # comment
        """)
        #expect(entries.count == 1)
        #expect(entries.first?.hostName == "dev.example.com")
        #expect(entries.first?.user == "developer")
        #expect(entries.first?.identityFile == "~/.ssh/key #1")
        #expect(warnings.isEmpty)
    }

    @Test func sshConfigRepeatedHostsKeepFirstValuesAndNegationsCannotImportExcludedHost() {
        let (entries, warnings) = SSHConfigParser.parse("""
        Host dev
          User first
        Host dev
          User second
          Port 2222
        Host excluded !excluded
          User forbidden
        """)
        #expect(entries.count == 1)
        #expect(entries.first?.user == "first")
        #expect(entries.first?.port == 2222)
        #expect(warnings.contains { $0.contains("negated Host block") })
    }

    @Test func sshConfigReportsUnsupportedOptionsAndRejectsInvalidPorts() {
        let (entries, warnings) = SSHConfigParser.parse("""
        User global
        Include ~/.ssh/config.d/*
        Host invalid
          User deploy
          Port 65536
        Host valid
          User deploy
          ProxyJump gateway
          ForwardAgent yes
        """)
        #expect(entries.map(\.alias) == ["valid"])
        #expect(warnings.contains { $0.contains("global User") })
        #expect(warnings.contains { $0.contains("Include") })
        #expect(warnings.contains { $0.contains("ProxyJump") })
        #expect(warnings.contains { $0.contains("ForwardAgent") })
        #expect(warnings.contains { $0.contains("Port is invalid") })
    }

    @Test @MainActor func sshConfigImportSkipsUnresolvedIdentityWithoutChangingSavedProfile() async throws {
        let suite = "sh.glas.tests.ssh-import.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        let manager = ServerManager(defaults: defaults)
        let original = ServerConfiguration(name: "dev", host: "original.example.com", username: "original")
        try await manager.addServerOrThrow(original)

        let result = await settings.importSSHConfig("""
        Host dev
          HostName changed.example.com
          User deploy
          IdentityFile ~/.ssh/not-imported
        """, serverManager: manager)

        #expect(result.imported == 0)
        #expect(result.updated == 0)
        #expect(result.skipped == 1)
        #expect(result.warnings.contains { $0.contains("Import the key") })
        #expect(manager.servers.first?.host == original.host)
        #expect(manager.servers.first?.authMethod == original.authMethod)
    }

    @Test @MainActor func sshConfigImportReportsPersistenceFailureWithoutPublishingProfile() async throws {
        let suite = "sh.glas.tests.ssh-import-failure.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        let manager = ServerManager(defaults: defaults, serverDataWriter: { _ in })
        let result = await settings.importSSHConfig("Host dev\n User deploy", serverManager: manager)
        #expect(result.imported == 0)
        #expect(result.skipped == 1)
        #expect(result.warnings.contains { $0.contains("Could not save") })
        #expect(manager.servers.isEmpty)
    }

    @Test func sshConfigParserMultipleHosts() {
        let input = """
        Host web1
          HostName web1.example.com
          User deploy
          Port 22

        Host web2
          HostName web2.example.com
          User deploy
          Port 2222
        """

        let (entries, warnings) = SSHConfigParser.parse(input)
        #expect(entries.count == 2)
        #expect(entries[0].alias == "web1")
        #expect(entries[1].alias == "web2")
        #expect(entries[1].port == 2222)
        #expect(warnings.isEmpty)
    }

    @Test func sshConfigParserSkipsWildcardHosts() {
        let input = """
        Host *
          ServerAliveInterval 60

        Host dev
          HostName dev.example.com
          User admin
        """

        let (entries, warnings) = SSHConfigParser.parse(input)
        #expect(entries.count == 1)
        #expect(entries.first?.alias == "dev")
        #expect(warnings.contains { $0.contains("wildcard") })
    }

    @Test func sshConfigParserHandlesComments() {
        let input = """
        # This is a comment
        Host myserver
          HostName server.example.com # inline comment
          User admin
          Port 22
        """

        let (entries, warnings) = SSHConfigParser.parse(input)
        #expect(entries.count == 1)
        #expect(entries.first?.hostName == "server.example.com")
        #expect(warnings.isEmpty)
    }

    @Test func sshConfigParserEmptyInput() {
        let (entries, warnings) = SSHConfigParser.parse("")
        #expect(entries.isEmpty)
        #expect(warnings.isEmpty)
    }

    private func makeCorruptedLegacyGlassTheme(
        id: UUID = UUID(),
        background: CodableColor? = nil,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 14
    ) -> TerminalTheme {
        let black = CodableColor(sRGBRed: 0, green: 0, blue: 0)
        let white = CodableColor(sRGBRed: 1, green: 1, blue: 1)
        let resolvedBackground = background ?? CodableColor(
            sRGBRed: 0,
            green: 0,
            blue: 0,
            alpha: 0.3
        )
        return TerminalTheme(
            id: id,
            name: "Glass Terminal",
            background: resolvedBackground,
            foreground: white,
            cursor: black,
            selection: black,
            black: black,
            red: black,
            green: black,
            yellow: black,
            blue: black,
            magenta: black,
            cyan: black,
            white: white,
            brightBlack: black,
            brightRed: black,
            brightGreen: black,
            brightYellow: black,
            brightBlue: black,
            brightMagenta: black,
            brightCyan: black,
            brightWhite: white,
            fontName: fontName,
            fontSize: fontSize
        )
    }

    @MainActor
    private func waitForPendingSynchronizations(
        _ expectedCount: Int,
        in store: FakeICloudSettingsStore
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while store.pendingSynchronizationCount < expectedCount,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return store.pendingSynchronizationCount >= expectedCount
    }

    private func makeICloudPayload(
        customID: UUID,
        customDeletedAt: Date?,
        modifiedAt: Date
    ) -> ICloudSettingsSyncPayload {
        let builtIn = TerminalTheme.default
        let custom = TerminalTheme.default.reidentified(id: customID, name: "Imported")
        return ICloudSettingsSyncPayload(
            themeRecords: [
                ICloudTerminalThemeRecord(
                    theme: makeICloudTheme(builtIn),
                    origin: .builtIn,
                    modifiedAt: modifiedAt,
                    deletedAt: nil
                ),
                ICloudTerminalThemeRecord(
                    theme: makeICloudTheme(custom),
                    origin: .appleTerminal,
                    modifiedAt: modifiedAt,
                    deletedAt: customDeletedAt
                ),
            ],
            selectedThemeID: customDeletedAt == nil ? customID : TerminalTheme.defaultID,
            selectionModifiedAt: modifiedAt,
            preferences: ICloudPortableTerminalPreferences(
                autoReconnect: true,
                confirmBeforeClosing: true,
                saveScrollback: true,
                maximumScrollbackLines: 10_000,
                bellEnabled: false,
                visualBell: true,
                cursorStyle: "Block",
                blinkingCursor: true,
                glassFrost: "ultraThin",
                windowOpacity: 0,
                blurBackground: 1,
                interactiveGlass: true,
                glassTint: "None"
            )
        )
    }



    @Test @MainActor
    func sftpSessionCannotBecomeATerminalWorkgroupTab() {
        let manager = SessionManager(loadImmediately: false)
        let server = ServerConfiguration(name: "Files", host: "example.test", username: "alice")
        let browser = TerminalSession(server: server, purpose: .sftp)
        manager.registerSession(browser)
        let workgroup = manager.createWorkgroup(name: "Terminals", colorTag: .blue)
        #expect(!manager.appendSession(browser, toWorkgroup: workgroup))
        #expect(manager.session(for: browser.id) != nil)
        manager.closeSession(browser)
        #expect(manager.session(for: browser.id) == nil)
    }

    private func makeICloudTheme(_ theme: TerminalTheme) -> ICloudTerminalTheme {
        ICloudTerminalTheme(
            id: theme.id,
            name: theme.name,
            background: makeICloudColor(theme.background),
            foreground: makeICloudColor(theme.foreground),
            cursor: makeICloudColor(theme.cursor),
            selection: makeICloudColor(theme.selection),
            ansiColors: theme.ansiColors.map(makeICloudColor),
            fontName: theme.fontName,
            fontSize: Double(theme.fontSize),
            preferredAppearance: theme.preferredAppearance
        )
    }

    private func makeICloudColor(_ color: CodableColor) -> ICloudTerminalColor {
        ICloudTerminalColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }
}

/// The owner, 2026-10-14: "a need to pause on device AI suggestions … it's monitoring the output of
/// an eval". On unless turned off; off stays off; a pause belongs to one terminal.
@Suite("Error suggestions can be paused or turned off")
@MainActor
struct ErrorSuggestionSettingTests {
    @Test("on by default; turned off, it stays off after a relaunch")
    func persists() {
        let suiteName = "sh.glas.test.error-suggestions.\(UUID().uuidString)"
        let defaults = UserDefaults.forTest(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        settings.loadPersistentStateIfNeeded()
        #expect(settings.errorSuggestions)
        settings.errorSuggestions = false
        settings.saveSettings()

        let relaunched = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
        relaunched.loadPersistentStateIfNeeded()
        #expect(!relaunched.errorSuggestions)
    }

    @Test("a pause is one terminal's: a new terminal is not paused")
    func pauseIsPerTerminal() {
        let server = ServerConfiguration(name: "alpha", host: "alpha.example", username: "ann")
        let paused = TerminalSession(server: server, terminalWriteSink: { _ in }, terminalResizeSink: { _, _ in })
        paused.errorSuggestionsPaused = true
        let other = TerminalSession(server: server, terminalWriteSink: { _ in }, terminalResizeSink: { _, _ in })
        #expect(!other.errorSuggestionsPaused)
    }
}
