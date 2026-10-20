//
//  Constants.swift
//  glas.sh
//
//  Typed constants for UserDefaults keys and Keychain service names
//

import Foundation
import GlassLayers

nonisolated enum UserDefaultsKeys {
    /// **No longer the production store (D26).** Saved servers live on their service links in the
    /// catalog; the composition root attaches `ServerPersistenceStore.catalog` at launch. This key
    /// backs `ServerPersistenceStore.live`, which is what a unit test, a preview or any context
    /// with no shell attached uses — and it is deliberately absent from both legacy migrations,
    /// because the decision was that the new build reads nothing old.
    static let servers = "servers"
    static let autoReconnect = "autoReconnect"
    static let confirmBeforeClosing = "confirmBeforeClosing"
    static let saveScrollback = "saveScrollback"
    static let maxScrollbackLines = "maxScrollbackLines"
    static let initialTerminalColumns = "initialTerminalColumns"
    static let initialTerminalRows = "initialTerminalRows"
    static let localShell = "localShell"
    static let localWorkingDirectory = "localWorkingDirectory"
    static let localTmux = "localTmux"
    /// Workgroups deleted on this device, so the deletion reaches the others (2026-10-08).
    static let layoutPresetTombstones = "layoutPresetTombstones"
    static let bellEnabled = "bellEnabled"
    static let visualBell = "visualBell"
    static let hostKeyVerificationMode = "hostKeyVerificationMode"
    static let cursorStyle = "cursorStyle"
    static let blinkingCursor = "blinkingCursor"
    static let pathPreviews = "pathPreviews"
    static let whenResized = "whenResized"
    static let errorSuggestions = "errorSuggestions"
    static let fontFollowsSystemTextSize = "fontFollowsSystemTextSize"
    static let joinsWrappedPastes = "joinsWrappedPastes"
    static let windowOpacity = "windowOpacity"
    static let blurBackground = "blurBackground"
    static let interactiveGlassEffects = "interactiveGlassEffects"
    static let glassTint = "glassTint"
    static let glassFrost = "glassFrost"
    static let backgroundFill = "backgroundFill"
    static let interactiveGlass = "interactiveGlass"
    static let sessionOverrides = "sessionOverrides"
    static let trustedHostKeys = "trustedHostKeys"
    static let hostTrustMigrationVersion = "hostTrustMigrationVersion"
    static let hostTrustMigrationReport = "hostTrustMigrationReport"
    static let credentialMigrationVersion = "credentialMigrationVersion"
    static let credentialMigrationReport = "credentialMigrationReport"
    static let sshKeys = "sshKeys"
    static let sshKeyDeletionJournal = "sshKeyDeletionJournal"
    static let theme = "theme"
    static let themeLibrary = "themeLibrary"
    static let iCloudSettingsSyncEnabled = "iCloudSettingsSyncEnabled"
    static let iCloudSettingsWriterID = "iCloudSettingsWriterID"
    static let snippets = "snippets"
    static let layoutPresets = "layoutPresets"
    static let macWorkspaceRestoration = "macWorkspaceRestoration"
    static let macWorkspaceSidebarVisibility = "macWorkspaceSidebarVisibility"
    static let tailscaleTailnet = "tailscaleTailnet"
    static let tailscaleAuthMethod = "tailscaleAuthMethod"
    static let focusEnvironmentStyle = "focusEnvironmentStyle"
    static let notificationOverlaysEnabled = "notificationOverlaysEnabled"
    // Legacy keys retained for one-time read-side migration in SettingsManager.
    static let glassMaterialStyle = "glassMaterialStyle"
}

nonisolated enum SharedDefaults {
    static let suiteName = GlassAppIdentity.appGroup

    /// A per-run defaults suite while a UI test is driving the app, so a test never writes into
    /// the user's real store.
    ///
    /// **The catalog was isolated and this was not.** `GlassPowerToolsApp.init` gives the shell an
    /// isolated directory under `--ui-testing`, but the terminal's servers, themes and preferences
    /// go through `SharedDefaults` — `UserDefaults.standard` on the Mac — which had no such
    /// treatment. Every UI run therefore appended its fixtures to the real saved-server list:
    /// 122 entries had accumulated there by 2026-09-13, of which four were genuine. They surfaced
    /// in Connect Saved Host, where a `probe@editable.example` is plainly not a machine anyone owns.
    ///
    /// Debug-only, and keyed on the same argument the shell uses, so there is one signal for
    /// "this is a test run" rather than two that can disagree.
    /// Computed rather than stored: `UserDefaults` is thread-safe but not `Sendable`, so a static
    /// constant of it is rejected under strict concurrency. Resolving it per access costs an
    /// argument scan and is only reached in a Debug test run.
    private static var testSuite: UserDefaults? { GlassUITestRun.defaults }

    /// True while a UI test drives the app (`--ui-testing <uuid>`). Its settings must not reach
    /// iCloud either: the key-value store is the person's own, shared with every device.
    static var isUITestRun: Bool { testSuite != nil }

    #if os(macOS)
    static let legacyMacBundleIdentifier = "sh.glas.mac"
    static let legacyMacDomainMigrationSentinel = "legacyMacDomainMigrationComplete"

    // The Mac terminal must remain outside App Sandbox so it can launch the
    // user's shell and PTYs. App Group containers require sandbox membership,
    // so Mac metadata belongs in its bundle-scoped defaults domain instead.
    static var defaults: UserDefaults { testSuite ?? .standard }
    #else
    static var defaults: UserDefaults { testSuite ?? UserDefaults(suiteName: suiteName)! }
    #endif

    static let schemaVersionKey = "sharedSchemaVersion"
    static let currentSchemaVersion = 1

    private static let migrationSentinel = "sharedDefaultsMigrationComplete"

    static func migrateIfNeeded() {
        let standard = UserDefaults.standard
        #if os(macOS)
        migrateLegacyMacDomainIfNeeded(
            legacyDomain: standard.persistentDomain(forName: legacyMacBundleIdentifier),
            destination: standard
        )
        #endif
        guard !standard.bool(forKey: migrationSentinel) else { return }

        // Neither `servers` nor `sshKeys` is in this list any more. D26 made the catalog the one
        // store for a connection and moved key *records* into the Keychain beside their material,
        // and the decision was explicitly that the new build reads nothing old. Host-key pins still
        // come across: they are still kept where they always were.
        for key in [UserDefaultsKeys.trustedHostKeys] {
            if let data = standard.data(forKey: key), defaults.data(forKey: key) == nil {
                defaults.set(data, forKey: key)
            }
        }

        standard.set(true, forKey: migrationSentinel)
    }

    #if os(macOS)
    private static let legacyMacNonSecretKeys: Set<String> = [
        // `servers` and `sshKeys` deliberately absent — see `migrateIfNeeded`.
        UserDefaultsKeys.autoReconnect,
        UserDefaultsKeys.confirmBeforeClosing,
        UserDefaultsKeys.saveScrollback,
        UserDefaultsKeys.maxScrollbackLines,
        UserDefaultsKeys.initialTerminalColumns,
        UserDefaultsKeys.initialTerminalRows,
        UserDefaultsKeys.bellEnabled,
        UserDefaultsKeys.visualBell,
        UserDefaultsKeys.hostKeyVerificationMode,
        UserDefaultsKeys.cursorStyle,
        UserDefaultsKeys.blinkingCursor,
        UserDefaultsKeys.windowOpacity,
        UserDefaultsKeys.blurBackground,
        UserDefaultsKeys.interactiveGlassEffects,
        UserDefaultsKeys.glassTint,
        UserDefaultsKeys.glassFrost,
        UserDefaultsKeys.backgroundFill,
        UserDefaultsKeys.interactiveGlass,
        UserDefaultsKeys.sessionOverrides,
        UserDefaultsKeys.theme,
        UserDefaultsKeys.themeLibrary,
        UserDefaultsKeys.iCloudSettingsSyncEnabled,
        UserDefaultsKeys.iCloudSettingsWriterID,
        UserDefaultsKeys.snippets,
        UserDefaultsKeys.layoutPresets,
        UserDefaultsKeys.macWorkspaceRestoration,
        UserDefaultsKeys.tailscaleTailnet,
        UserDefaultsKeys.tailscaleAuthMethod,
        UserDefaultsKeys.focusEnvironmentStyle,
        UserDefaultsKeys.notificationOverlaysEnabled,
        UserDefaultsKeys.glassMaterialStyle,
    ]

    static func migrateLegacyMacDomainIfNeeded(
        legacyDomain: [String: Any]?,
        destination: UserDefaults
    ) {
        guard !destination.bool(forKey: legacyMacDomainMigrationSentinel),
              let legacyDomain else { return }

        // Settings only. The saved-server branch that used to live here — sanitising a legacy
        // catalog before copying it across — went with D26: `servers` is no longer a key this
        // build reads, from any domain.
        let copiedEveryPendingValue = true
        for (key, value) in legacyDomain
        where isLegacyMacNonSecretKey(key) && destination.object(forKey: key) == nil {
            destination.set(value, forKey: key)
        }

        if copiedEveryPendingValue {
            destination.set(true, forKey: legacyMacDomainMigrationSentinel)
        }
    }

    private static func isLegacyMacNonSecretKey(_ key: String) -> Bool {
        legacyMacNonSecretKeys.contains(key)
            || key.hasPrefix("\(UserDefaultsKeys.macWorkspaceRestoration).")
    }

    private static func sanitizedLegacyServerCatalog(_ value: Any) -> Data? {
        guard let data = value as? Data,
              var servers = try? JSONDecoder().decode([ServerConfiguration].self, from: data) else {
            return nil
        }
        for index in servers.indices {
            servers[index].trustedHostKeys = nil
        }
        return try? JSONEncoder().encode(servers)
    }
    #endif
}
