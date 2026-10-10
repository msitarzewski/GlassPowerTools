//
//  GlassEditorWindowSettings.swift
//  Glass Power Tools — GlassEditor
//
//  W23 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
//  overridden per window", for every kind of window. W22 built the mechanism in GlassLayers
//  (`GlassWindowOverrides`); this is the editor's part of it.
//
//  An editor window keeps its own glass — Appearance's opacity, frost and material
//  (`GlassLayerSettings`) — and its own text: size, line numbers and wrapping, the three settings
//  in Settings ▸ Editor. Those are all the editor's settings there are. The text's colours follow
//  the system's light or dark appearance and are no setting at all; the font is the system's
//  monospaced one, which nothing can change; tab width, invisibles and the preview layout are not
//  settings in this editor either (the preview is chosen per document, from the toolbar).
//
//  **Where a window sits among the text levels.** A document's text comes from the most specific
//  level that says something: the file, then its project, then **the window**, then Settings ▸
//  Editor. The window takes the place of the app's defaults for everything shown in it — what the
//  owner asked for, the system settings overridden per window — and a project or a file that
//  disagrees still does, because they are about the text itself (a repository at 11 pt, a
//  generated file unwrapped) where a window is about where it is being read.
//
//  **Kept on this device, with the window's project.** An editor window is not restored after a
//  relaunch (decided 2026-10-08): what comes back is its project, one per window (2026-10-08), so
//  the project is what a window's settings are kept under — and they come back when the project
//  opens in a window again. They stay on this device and do not travel with the project's synced
//  record, because what they override doesn't travel either: Settings ▸ Editor and Appearance are
//  each device's own, and a headset window read at arm's length, or its glass against a room, is
//  no answer for a Mac at a desk. What does travel is the project's own text settings, which are
//  about the project (`GlassEditorProject.textOverrides`). A window with no project — loose files,
//  a new document — keeps its settings while it is open.
//

import Foundation
import GlassLayers
import GlassEditorCore

/// The editor settings a window can keep for itself (W23), each under a stable key. The window's
/// glass is Appearance's (`GlassLayerSettings`).
enum GlassEditorWindowSettings {
    /// Settings ▸ Editor ▸ Text Size, in whole points within the editor's range.
    static let fontSize = GlassWindowSetting<Double>("editor.fontSize", title: "Text Size") { size in
        guard size.isFinite else { return nil }
        let range = GlassEditorTextOverrides.fontSizeRange
        return min(range.upperBound, max(range.lowerBound, size.rounded()))
    }
    /// Settings ▸ Editor ▸ Show Line Numbers.
    static let showsLineNumbers = GlassWindowSetting<Bool>("editor.showsLineNumbers", title: "Show Line Numbers")
    /// Settings ▸ Editor ▸ Wrap Long Lines.
    static let wrapsLines = GlassWindowSetting<Bool>("editor.wrapsLines", title: "Wrap Long Lines")

    /// The text settings, which a project's and a file's own settings sit over.
    static var textKeys: Set<String> { [fontSize.key, showsLineNumbers.key, wrapsLines.key] }
}

extension GlassEditorConfiguration {
    /// This configuration with a window's text settings over it, field by field: what everything in
    /// that window starts from before its project's and its file's own settings.
    func overlaid(by window: GlassWindowOverrides) -> GlassEditorConfiguration {
        var configuration = self
        configuration.fontSize = window.value(of: GlassEditorWindowSettings.fontSize, over: fontSize)
        configuration.showsLineNumbers = window.value(of: GlassEditorWindowSettings.showsLineNumbers,
                                                      over: showsLineNumbers)
        configuration.wrapsLines = window.value(of: GlassEditorWindowSettings.wrapsLines, over: wrapsLines)
        return configuration
    }
}

// MARK: - Kept on this device

/// One editor window as this device keeps it between launches: today, its own settings. Kept by
/// project (`GlassEditorProjectLibrary.windowSettings(for:)`), never synced.
///
/// Written with `encodeIfNotEmpty` and read leniently, like every record that holds a window's
/// settings (W22): a record that can't be read is a window that sets nothing, and keys a newer
/// build wrote are kept.
struct GlassEditorWindowRecord: Codable, Equatable, Sendable {
    var windowSettings: GlassWindowOverrides

    init(windowSettings: GlassWindowOverrides) {
        self.windowSettings = windowSettings
    }

    private enum CodingKeys: String, CodingKey {
        case windowSettings
    }

    /// Never throws: anything but an object is a window that sets nothing.
    init(from decoder: any Decoder) {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            windowSettings = GlassWindowOverrides()
            return
        }
        windowSettings = GlassWindowOverrides.lenientlyDecoded(from: container, forKey: .windowSettings)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfNotEmpty(windowSettings, forKey: .windowSettings)
    }
}

/// This device's editor windows, by the project each one shows.
struct GlassEditorWindowRecords: Equatable, Sendable {
    /// One per project at most, and no more than the projects the list can hold.
    static let maximumCount = GlassEditorProjectsPayload.maximumRecordCount

    private(set) var byProject: [GlassEditorProject.ID: GlassEditorWindowRecord] = [:]

    init() {}

    /// What the window showing `project` sets: nothing, unless it set something.
    func settings(for project: GlassEditorProject.ID) -> GlassWindowOverrides {
        byProject[project]?.windowSettings ?? GlassWindowOverrides()
    }

    /// Keeps `settings` for the window showing `project`; an empty overlay keeps no record at all.
    mutating func set(_ settings: GlassWindowOverrides, for project: GlassEditorProject.ID) {
        guard !settings.isEmpty else {
            byProject.removeValue(forKey: project)
            return
        }
        guard byProject[project] != nil || byProject.count < Self.maximumCount else { return }
        byProject[project] = GlassEditorWindowRecord(windowSettings: settings)
    }

    mutating func forget(_ project: GlassEditorProject.ID) {
        byProject.removeValue(forKey: project)
    }

    /// The stored form: one JSON object, project id to record.
    func encoded() -> Data? {
        let records = Dictionary(uniqueKeysWithValues: byProject.map { ($0.key.uuidString, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(records)
    }

    /// Read leniently: storage that isn't this shape is no records, an entry under something other
    /// than a project id is dropped, and so is a record that sets nothing.
    static func decoded(from data: Data?) -> GlassEditorWindowRecords {
        var result = GlassEditorWindowRecords()
        guard let data,
              let stored = try? JSONDecoder().decode([String: GlassEditorWindowRecord].self, from: data) else {
            return result
        }
        for key in stored.keys.sorted() {
            guard let id = UUID(uuidString: key), let record = stored[key] else { continue }
            result.set(record.windowSettings, for: id)
        }
        return result
    }
}
