//
//  ICloudSettingsSyncService.swift
//  Glass Power Tools — GlassTerminal
//
//  The terminal's iCloud-synced payload (portable preferences and theme records) over the
//  shell's GlassSettingsSyncService. The service core moved to GlassShell on 2026-09-10; the
//  names glas.sh used stay as typealiases so its call sites and tests are unchanged.
//

import Foundation
import GlassShell

typealias ICloudSettingsSyncStatus = GlassSettingsSyncStatus
typealias ICloudSettingsStoreChangeReason = GlassSettingsStoreChangeReason
typealias ICloudSettingsStoreChange = GlassSettingsStoreChange
typealias ICloudSettingsKeyValueStore = GlassSettingsKeyValueStore
typealias NSUbiquitousSettingsKeyValueStore = GlassUbiquitousSettingsStore
typealias ICloudSettingsSyncEnvelope = GlassSettingsSyncEnvelope<ICloudSettingsSyncPayload>
typealias ICloudSettingsMergeResult = GlassSettingsMergeResult<ICloudSettingsSyncPayload>
typealias ICloudSettingsSyncError = GlassSettingsSyncError
typealias ICloudSettingsSyncService = GlassSettingsSyncService<ICloudSettingsSyncPayload>

nonisolated extension ICloudSettingsSyncPayload: GlassSettingsSyncPayload {
    func converged(with other: Self) -> Self { mergingThemeRecords(with: other) }
}

extension GlassSettingsSyncService where Payload == ICloudSettingsSyncPayload {
    /// The key glas.sh has always used; existing synced settings are found under it.
    static var terminalStoreKey: String { "terminal-settings-envelope-v1" }

    /// The labels deliberately differ from the shell's designated initializer so these forward
    /// to it instead of to themselves.
    convenience init(store: any GlassSettingsKeyValueStore, writerID: UUID = UUID()) {
        self.init(store: store, writerID: writerID, storeKey: Self.terminalStoreKey, maximumEncodedBytes: 384 * 1024)
    }

    convenience init(writerID: UUID = UUID()) {
        self.init(store: GlassUbiquitousSettingsStore(), writerID: writerID)
    }
}

nonisolated struct ICloudTerminalColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    func validate() throws {
        let components = [red, green, blue, alpha]
        guard components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ICloudSettingsSyncError.invalidPayload("Theme colors must use finite 0...1 components.")
        }
    }
}

/// Portable terminal appearance. ANSI colors are stored in terminal index
/// order: normal 0...7 followed by bright 8...15.
nonisolated struct ICloudTerminalTheme: Codable, Equatable, Identifiable, Sendable {
    static let maximumNameLength = TerminalTheme.maximumNameLength
    static let maximumFontNameLength = TerminalTheme.maximumFontNameLength

    let id: UUID
    var name: String
    var background: ICloudTerminalColor
    var foreground: ICloudTerminalColor
    var cursor: ICloudTerminalColor
    var selection: ICloudTerminalColor
    var ansiColors: [ICloudTerminalColor]
    var fontName: String
    var fontSize: Double
    var preferredAppearance: TerminalThemeAppearance? = nil

    func reidentified(id: UUID) -> Self {
        Self(id: id, name: name, background: background, foreground: foreground, cursor: cursor,
             selection: selection, ansiColors: ansiColors, fontName: fontName, fontSize: fontSize,
             preferredAppearance: preferredAppearance)
    }

    func validate() throws {
        guard !name.isEmpty, name.count <= Self.maximumNameLength else {
            throw ICloudSettingsSyncError.invalidPayload("Theme names must contain 1...128 characters.")
        }
        guard !fontName.isEmpty, fontName.count <= Self.maximumFontNameLength else {
            throw ICloudSettingsSyncError.invalidPayload("Theme font names must contain 1...128 characters.")
        }
        guard fontSize.isFinite,
              (Double(TerminalTheme.minimumFontSize)...Double(TerminalTheme.maximumFontSize)).contains(fontSize) else {
            throw ICloudSettingsSyncError.invalidPayload(
                "Theme font sizes must be within \(Int(TerminalTheme.minimumFontSize))...\(Int(TerminalTheme.maximumFontSize)) points.")
        }
        guard ansiColors.count == 16 else {
            throw ICloudSettingsSyncError.invalidPayload("Terminal themes require exactly 16 ANSI colors.")
        }

        try background.validate()
        try foreground.validate()
        try cursor.validate()
        try selection.validate()
        for color in ansiColors {
            try color.validate()
        }
    }
}

/// Synchronizes the library's conflict-resolution metadata along with its
/// visual theme. Deletion tombstones are required so an offline device cannot
/// resurrect a theme that was removed elsewhere.
nonisolated struct ICloudTerminalThemeRecord: Codable, Equatable, Identifiable, Sendable {
    let theme: ICloudTerminalTheme
    let origin: TerminalThemeOrigin
    let modifiedAt: Date
    let deletedAt: Date?

    var id: UUID { theme.id }
    var isDeleted: Bool { deletedAt != nil }

    func validate() throws {
        try theme.validate()
        guard modifiedAt.timeIntervalSinceReferenceDate.isFinite,
              deletedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw ICloudSettingsSyncError.invalidPayload("Theme change dates must be finite.")
        }
    }
}

/// Explicit allowlist of portable, non-secret preferences. This type cannot
/// represent credentials, saved servers, host trust, SSH keys, snippets,
/// layouts, per-server overrides, recordings, or live session state.
nonisolated struct ICloudPortableTerminalPreferences: Codable, Equatable, Sendable {
    var autoReconnect: Bool
    var confirmBeforeClosing: Bool
    var saveScrollback: Bool
    var maximumScrollbackLines: Int
    /// Additive optional fields keep version-one payloads bidirectionally
    /// decodable while newer devices synchronize their initial PTY fallback.
    var initialTerminalColumns: Int? = nil
    var initialTerminalRows: Int? = nil
    var bellEnabled: Bool
    var visualBell: Bool
    var cursorStyle: String
    var blinkingCursor: Bool
    var glassFrost: String
    var windowOpacity: Double
    var blurBackground: Double
    var interactiveGlass: Bool
    var glassTint: String
    /// Show previews (2026-10-16), optional so a payload from before it still decodes.
    var pathPreviews: String? = nil
    /// When resized (D75, 2026-10-16), optional for the same reason.
    var whenResized: String? = nil
    /// Focus Mode's environment on Vision Pro (2026-10-26), optional for the same reason.
    var focusEnvironment: String? = nil
    /// Focus Mode opening immersed on Vision Pro (2026-10-26), optional for the same reason.
    var focusOpensImmersed: Bool? = nil
    /// Focus Mode's room sound on Vision Pro, 0…1 (2026-10-27), optional for the same reason.
    var focusEnvironmentSound: Double? = nil

    func validate() throws {
        guard (0...100_000).contains(maximumScrollbackLines) else {
            throw ICloudSettingsSyncError.invalidPayload("Maximum scrollback must be within 0...100000 lines.")
        }
        switch (initialTerminalColumns, initialTerminalRows) {
        case (nil, nil):
            break
        case (.some(let columns), .some(let rows))
            where TerminalGeometry.contains(rows: rows, columns: columns):
            break
        default:
            throw ICloudSettingsSyncError.invalidPayload(
                "Initial terminal dimensions must include 20...500 columns and 8...300 rows."
            )
        }
        guard !cursorStyle.isEmpty, cursorStyle.count <= 64 else {
            throw ICloudSettingsSyncError.invalidPayload("Cursor styles must contain 1...64 characters.")
        }
        guard !glassFrost.isEmpty, glassFrost.count <= 64 else {
            throw ICloudSettingsSyncError.invalidPayload("Glass material names must contain 1...64 characters.")
        }
        guard !glassTint.isEmpty, glassTint.count <= 64 else {
            throw ICloudSettingsSyncError.invalidPayload("Glass tint values must contain 1...64 characters.")
        }
        if let focusEnvironmentSound, !focusEnvironmentSound.isFinite || !(0...1).contains(focusEnvironmentSound) {
            throw ICloudSettingsSyncError.invalidPayload("Focus Mode's room sound must be a finite 0...1 value.")
        }
        if let focusEnvironment, focusEnvironment.count > FocusEnvironmentFiles.longestID {
            throw ICloudSettingsSyncError.invalidPayload("Focus environments must be named in at most \(FocusEnvironmentFiles.longestID) characters.")
        }
        guard windowOpacity.isFinite, (0...1).contains(windowOpacity),
              blurBackground.isFinite, (0...1).contains(blurBackground) else {
            throw ICloudSettingsSyncError.invalidPayload("Terminal opacity and blur must be finite 0...1 values.")
        }
    }
}

nonisolated struct ICloudSettingsSyncPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumThemeRecordCount = 128

    let schemaVersion: Int
    var themeRecords: [ICloudTerminalThemeRecord]
    var selectedThemeID: UUID
    var selectionModifiedAt: Date
    var preferences: ICloudPortableTerminalPreferences

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        themeRecords: [ICloudTerminalThemeRecord],
        selectedThemeID: UUID,
        selectionModifiedAt: Date,
        preferences: ICloudPortableTerminalPreferences
    ) {
        self.schemaVersion = schemaVersion
        self.themeRecords = themeRecords
        self.selectedThemeID = selectedThemeID
        self.selectionModifiedAt = selectionModifiedAt
        self.preferences = preferences
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ICloudSettingsSyncError.unsupportedPayloadSchema(schemaVersion)
        }
        guard themeRecords.count <= Self.maximumThemeRecordCount else {
            throw ICloudSettingsSyncError.invalidPayload("At most 128 terminal theme records can be synchronized.")
        }

        var themeIDs = Set<UUID>()
        var activeThemeIDs = Set<UUID>()
        var activeThemeCount = 0
        var activeBuiltInCount = 0
        for record in themeRecords {
            guard themeIDs.insert(record.id).inserted else {
                throw ICloudSettingsSyncError.invalidPayload("Terminal theme identifiers must be unique.")
            }
            try record.validate()
            if record.origin == .builtIn, record.isDeleted {
                throw ICloudSettingsSyncError.invalidPayload("The built-in terminal theme cannot be deleted.")
            }
            // A device on an older build still sends the built-in theme under its former identifier;
            // `canonicalizingBuiltInTheme()` re-identifies it before a push, the library on merge.
            if record.origin == .builtIn,
               record.id != TerminalTheme.defaultID, record.id != TerminalTheme.legacyDefaultID {
                throw ICloudSettingsSyncError.invalidPayload("The built-in terminal theme identifier is invalid.")
            }
            if !record.isDeleted {
                activeThemeIDs.insert(record.id)
                activeThemeCount += 1
                if record.origin == .builtIn { activeBuiltInCount += 1 }
            }
        }
        guard activeThemeCount <= TerminalThemeLibrary.maximumThemeCount else {
            throw ICloudSettingsSyncError.invalidPayload("At most 64 active terminal themes can be synchronized.")
        }
        guard activeBuiltInCount == 1 else {
            throw ICloudSettingsSyncError.invalidPayload("The synchronized library must contain one active built-in theme.")
        }
        guard activeThemeIDs.contains(selectedThemeID) else {
            throw ICloudSettingsSyncError.invalidPayload("The selected terminal theme must exist in the synchronized library.")
        }
        guard selectionModifiedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ICloudSettingsSyncError.invalidPayload("The theme selection change date must be finite.")
        }
        try preferences.validate()
    }

    /// Unions record metadata before an outgoing write. This makes a stale
    /// device retain remote tombstones instead of overwriting them merely by
    /// publishing the next envelope revision.
    func mergingThemeRecords(with other: Self) -> Self {
        let mine = canonicalizingBuiltInTheme()
        let other = other.canonicalizingBuiltInTheme()
        var merged = Dictionary(uniqueKeysWithValues: mine.themeRecords.map { ($0.id, $0) })
        for record in other.themeRecords {
            guard let existing = merged[record.id] else {
                merged[record.id] = record
                continue
            }
            if Self.recordIsNewer(record, than: existing) {
                merged[record.id] = record
            }
        }

        let useOtherSelection = other.selectionModifiedAt > mine.selectionModifiedAt
            || (other.selectionModifiedAt == mine.selectionModifiedAt
                && other.selectedThemeID.uuidString > mine.selectedThemeID.uuidString)
        let mergedRecords = Array(merged.values)
        var resolvedSelection = useOtherSelection ? other.selectedThemeID : mine.selectedThemeID
        let activeIDs = Set(mergedRecords.filter { !$0.isDeleted }.map(\.id))
        if !activeIDs.contains(resolvedSelection),
           let fallback = mergedRecords
            .filter({ !$0.isDeleted })
            .sorted(by: { $0.id.uuidString < $1.id.uuidString })
            .first {
            resolvedSelection = fallback.id
        }
        return Self(
            themeRecords: mergedRecords,
            selectedThemeID: resolvedSelection,
            selectionModifiedAt: max(mine.selectionModifiedAt, other.selectionModifiedAt),
            preferences: preferences
        )
    }

    /// The built-in theme as one record under the current identifier. glas.sh and this app's
    /// builds before 2026-09-27 send it under `legacyDefaultID`, and they share this store
    /// (`GPT_KVSTORE_SUFFIX`), so a union by identifier with this device's record held the
    /// built-in theme twice: `validate()` refused the result, and while such an envelope was
    /// stored no push could land (W18, 2026-10-10). As `TerminalThemeLibrary.canonicalize()`
    /// does, the newest built-in record wins, so neither device's later edit is lost.
    func canonicalizingBuiltInTheme() -> Self {
        let builtIns = themeRecords.filter { $0.origin == .builtIn }
        guard builtIns.contains(where: { $0.id != TerminalTheme.defaultID })
                || selectedThemeID == TerminalTheme.legacyDefaultID else { return self }
        var records = themeRecords.filter { $0.origin != .builtIn }
        if let newest = builtIns.max(by: { Self.recordIsNewer($1, than: $0) }) {
            records.append(ICloudTerminalThemeRecord(
                theme: newest.theme.reidentified(id: TerminalTheme.defaultID),
                origin: .builtIn,
                modifiedAt: newest.modifiedAt,
                deletedAt: newest.deletedAt
            ))
        }
        return Self(
            schemaVersion: schemaVersion,
            themeRecords: records,
            selectedThemeID: selectedThemeID == TerminalTheme.legacyDefaultID
                ? TerminalTheme.defaultID : selectedThemeID,
            selectionModifiedAt: selectionModifiedAt,
            preferences: preferences
        )
    }

    private static func recordIsNewer(
        _ candidate: ICloudTerminalThemeRecord,
        than existing: ICloudTerminalThemeRecord
    ) -> Bool {
        let candidateDate = max(candidate.modifiedAt, candidate.deletedAt ?? .distantPast)
        let existingDate = max(existing.modifiedAt, existing.deletedAt ?? .distantPast)
        if candidateDate != existingDate { return candidateDate > existingDate }
        return stableRecordKey(candidate) > stableRecordKey(existing)
    }

    private static func stableRecordKey(_ record: ICloudTerminalThemeRecord) -> String {
        let theme = record.theme
        let colors = ([theme.background, theme.foreground, theme.cursor, theme.selection]
            + theme.ansiColors)
            .map { "\($0.red),\($0.green),\($0.blue),\($0.alpha)" }
            .joined(separator: "|")
        return [
            record.origin.rawValue,
            record.deletedAt?.timeIntervalSinceReferenceDate.description ?? "",
            theme.id.uuidString,
            theme.name,
            theme.fontName,
            theme.fontSize.description,
            theme.preferredAppearance?.rawValue ?? "",
            colors,
        ].joined(separator: "|")
    }
}

