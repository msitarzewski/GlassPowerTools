//
//  WorkgroupEditorView.swift
//  Glass Power Tools — GlassTerminal
//
//  Moved verbatim from glas.sh's ConnectionManagerView.swift (lines 2591-3319) on 2026-09-10 when the shell
//  took over the connection library. The workgroup editor and its tab editor.
//

import SwiftUI
import GlassLayers
import GlassConnectionUI
import GlassShell

struct WorkgroupEditorContext: Identifiable {
    let id = UUID()
    let original: LayoutPreset?
    let name: String
    let colorTag: ServerColorTag
    let sessionIntents: [LayoutPreset.SessionIntent]
    var workspaceLayout: LayoutPreset.WorkspaceLayout? = nil
    var openingView: LayoutPreset.OpeningView = .tabs
    var autoFocusOnActivity = LayoutPreset.followsActivityByDefault
    /// The settings the workgroup's window opens with (W20's look, W22): a captured window's, or
    /// the one being edited's. The editor changes their Look and Text (D84) and keeps the rest.
    var windowSettings = GlassWindowOverrides()
    /// Its databases and remote desktops (B-F40), by their library services' endpoints.
    var services: [UUID] = []

    static func new(
        name: String = "Workgroup",
        colorTag: ServerColorTag = .blue,
        sessionIntents: [LayoutPreset.SessionIntent] = []
    ) -> Self {
        Self(
            original: nil,
            name: name,
            colorTag: colorTag,
            sessionIntents: sessionIntents
        )
    }

    static func edit(_ preset: LayoutPreset) -> Self {
        Self(
            original: preset,
            name: preset.name,
            colorTag: preset.colorTag,
            sessionIntents: preset.sessionIntents,
            workspaceLayout: preset.workspaceLayout,
            openingView: preset.openingView,
            autoFocusOnActivity: preset.autoFocusOnActivity,
            windowSettings: preset.windowSettings,
            services: preset.services
        )
    }

    static func duplicate(_ preset: LayoutPreset) -> Self {
        let copyName = String("\(preset.name) Copy".prefix(LayoutPreset.maximumNameLength))
        return Self(
            original: nil,
            name: copyName,
            colorTag: preset.colorTag,
            // A copy opens terminals of its own, never the original's tmux sessions (W4b).
            sessionIntents: preset.sessionIntents.map { intent in
                var copy = intent
                copy.tmuxSession = nil
                return copy
            },
            workspaceLayout: preset.workspaceLayout,
            openingView: preset.openingView,
            autoFocusOnActivity: preset.autoFocusOnActivity,
            windowSettings: preset.windowSettings,
            services: preset.services
        )
    }

    /// The window settings the saved workgroup keeps (W20, W22), as the editor left them
    /// (`edited`, its Look). A window saved as a workgroup takes the window's, none included, and
    /// so does a copy or an edit of a workgroup keep its own; one made by hand keeps those of the
    /// workgroup it replaces, as it keeps how that one opens, but the look it was shown here: the
    /// editor shows the look a workgroup has, and None chosen there is none.
    func windowSettingsToSave(_ edited: GlassWindowOverrides, replacing replaced: LayoutPreset?) -> GlassWindowOverrides {
        if workspaceLayout != nil || original != nil || !windowSettings.isEmpty { return edited }
        return (replaced?.windowSettings ?? GlassWindowOverrides())
            .removing(TerminalWindowSettings.lookStyleKeys)
            .merging(edited)
    }

    /// As opened, with nothing changed in the editor.
    func windowSettingsToSave(replacing replaced: LayoutPreset?) -> GlassWindowOverrides {
        windowSettingsToSave(windowSettings, replacing: replaced)
    }

    /// Saved as it is: a new Workgroup goes straight into the panel, ready to name (2026-11-19, no editor sheet).
    /// Replacing one keeps its identity, so every device updates that Workgroup rather than gaining a second, and how
    /// it opens; a window saved over it brings its terminals, while its databases and desktops stay.
    func savedPreset(replacing replaced: LayoutPreset? = nil) -> LayoutPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var preset = LayoutPreset(
            id: replaced?.id ?? UUID(),
            name: String((trimmed.isEmpty ? "Workgroup" : trimmed).prefix(LayoutPreset.maximumNameLength)),
            colorTag: colorTag,
            sessionIntents: sessionIntents,
            createdAt: replaced?.createdAt ?? Date(),
            lastUsed: replaced?.lastUsed
        )
        preset.workspaceLayout = workspaceLayout
        preset.openingView = replaced?.openingView ?? openingView
        preset.autoFocusOnActivity = replaced?.autoFocusOnActivity ?? autoFocusOnActivity
        preset.windowSettings = windowSettingsToSave(replacing: replaced)
        preset.services = services.isEmpty ? (replaced?.services ?? []) : services
        return preset
    }
}

struct WorkgroupTabDraft: Identifiable {
    let id: UUID
    /// Another kind of terminal is another machine: the tmux session stays with the old one.
    var kind: LayoutPreset.SessionIntent.Kind {
        didSet { if kind != oldValue { tmuxSession = nil; macServerID = nil } }
    }
    /// Another server, the same: a session lives on its host (W4b).
    var serverID: UUID? {
        didSet { if serverID != oldValue { tmuxSession = nil } }
    }
    var label: String
    var startupCommand: String
    var localShell: String = ""
    var localDirectory: String = ""
    /// W4b: the tmux session the tab opens on, kept through an edit — the editor rebuilds every
    /// terminal from its draft, and a name left out here was lost on save.
    var tmuxSession: String? = nil
    /// A plain shell by choice (2026-10-12), kept through an edit for the same reason.
    var withoutTmux = false
    /// The Mac a local tab lives on (2026-10-29), kept through an edit on any device.
    var macServerID: UUID? = nil

    init(
        id: UUID = UUID(),
        kind: LayoutPreset.SessionIntent.Kind,
        serverID: UUID? = nil,
        label: String = "",
        startupCommand: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.serverID = serverID
        self.label = label
        self.startupCommand = startupCommand
    }

    init(intent: LayoutPreset.SessionIntent) {
        self.init(
            kind: intent.kind,
            serverID: intent.serverID,
            label: intent.label ?? "",
            startupCommand: intent.startupCommand ?? ""
        )
        localShell = intent.localShell ?? ""
        localDirectory = intent.localDirectory ?? ""
        tmuxSession = intent.tmuxSession
        withoutTmux = intent.withoutTmux
        macServerID = intent.macServerID
    }

    var intent: LayoutPreset.SessionIntent {
        LayoutPreset.SessionIntent(
            kind: kind,
            serverID: kind == .ssh ? serverID : nil,
            label: label,
            startupCommand: startupCommand,
            localShell: kind == .local ? localShell : nil,
            localDirectory: kind == .local ? localDirectory : nil,
            tmuxSession: tmuxSession,
            withoutTmux: withoutTmux,
            macServerID: macServerID
        )
    }

    func validationMessage(servers: [ServerConfiguration]) -> String? {
        if kind == .ssh {
            guard let serverID, servers.contains(where: { $0.id == serverID }) else {
                return "Choose a saved connection."
            }
        }
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count <= LayoutPreset.SessionIntent.maximumLabelLength,
              !label.utf8.contains(0) else { return "Enter a label no longer than \(LayoutPreset.SessionIntent.maximumLabelLength) characters without null characters." }
        let command = startupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !command.isEmpty, TerminalStartupCommandTicket(command: command) == nil {
            return "Use a single-line startup command no larger than 4 KB."
        }
        if kind == .local {
            for path in [localShell, localDirectory] {
                let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && (!(value.hasPrefix("/") || value == "~" || value.hasPrefix("~/")) || value.utf8.contains(0)) {
                    return "Use an absolute path or ~ for the shell and working directory."
                }
            }
        }
        return nil
    }
}

/// A workgroup's database or desktop (B-F40), as Favorites names it, with a way to take it out;
/// one that has left the library says so.
struct WorkgroupServiceRow: View {
    let description: GlassFavoriteDescription?
    var remove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let description {
                GlassServiceIcon(description.symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(description.title)
                    Text(description.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No longer in your library").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let remove {
                Button("Remove \(description?.title ?? "Service")", systemImage: "minus.circle.fill", role: .destructive, action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
        }
    }
}
