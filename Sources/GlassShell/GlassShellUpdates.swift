//
//  GlassShellUpdates.swift
//  Glass Power Tools — GlassShell
//
//  Updates for the Mac app, which is distributed outside the Mac App Store (D38) and so has no
//  system updater. Sparkle fetches the feed named in Info.plist (`SUFeedURL`) and installs only an
//  update signed with the EdDSA key whose public half is `SUPublicEDKey`. Both come from
//  `Config/Identity.xcconfig`; a build without them — a fork, or before the signing key exists —
//  has updates switched off and says so, rather than failing when someone checks.
//

#if os(macOS) && canImport(Sparkle)
import AppKit
import Observation
import Sparkle
import SwiftUI

@MainActor
@Observable
public final class GlassShellUpdates {
    public static let shared = GlassShellUpdates()

    /// Whether this build names a feed and the key its updates must be signed with.
    public let isConfigured: Bool
    public private(set) var automaticallyChecks = false
    public private(set) var lastChecked: Date?
    public private(set) var canCheck = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private init() {
        isConfigured = Self.infoValue("SUFeedURL") != nil && Self.infoValue("SUPublicEDKey") != nil
    }

    /// Starts Sparkle's scheduled checks, if this build is configured. Call once at launch. Sparkle
    /// asks on the second launch whether to check automatically; nothing is fetched before that
    /// unless someone chooses Check for Updates.
    public func start() {
        guard isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        lastChecked = updater.lastUpdateCheckDate
        canCheck = updater.canCheckForUpdates
        // Sparkle changes these itself — the second-launch answer, a finished check, a check in
        // progress — always on the main thread.
        observations = [
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyChecks = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.lastUpdateCheckDate) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.lastChecked = updater.lastUpdateCheckDate }
            },
            updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
        ]
    }

    public func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    public func setAutomaticallyChecks(_ value: Bool) {
        controller?.updater.automaticallyChecksForUpdates = value
    }

    /// A value from Info.plist, unless it is empty or an unexpanded build setting.
    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.contains("$(") ? nil : trimmed
    }
}

/// Application ▸ Check for Updates…, after About.
public struct GlassShellUpdateCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { GlassShellUpdates.shared.checkForUpdates() }
                .disabled(!GlassShellUpdates.shared.isConfigured || !GlassShellUpdates.shared.canCheck)
        }
    }
}

/// The update controls in Settings ▸ About.
struct GlassShellUpdateSettings: View {
    private let updates = GlassShellUpdates.shared

    var body: some View {
        if updates.isConfigured {
            VStack(spacing: 6) {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automaticallyChecks },
                    set: { updates.setAutomaticallyChecks($0) }))
                    .toggleStyle(.checkbox)
                HStack(spacing: 8) {
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheck)
                    if let lastChecked = updates.lastChecked {
                        Text("Last checked \(lastChecked.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
        } else {
            Text("This build does not update itself.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
#endif
