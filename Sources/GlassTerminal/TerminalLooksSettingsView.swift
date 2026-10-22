//
//  TerminalLooksSettingsView.swift
//  Glass Power Tools — GlassTerminal
//
//  This Window's Look and Text Glow (D84): what the window shows behind its terminals' text, how
//  readable the text stays over it, the text's palette and its glow. Every row is one of the
//  window's settings, with ↺ back to none; Start From sets them all at once.
//
//  A picture is chosen here, or dropped on the well: a picture dropped on a terminal is a file to
//  type or upload, as it has always been (`TerminalDroppedPaths`).
//

import SwiftUI
import UniformTypeIdentifiers
import GlassLayers
import GlassConnectionUI

struct TerminalLooksSettingsView: View {
    @Binding var settings: GlassWindowOverrides
    /// What the look is drawn behind, as the footer says it: this window's tabs, or a saved
    /// Workgroup's.
    var subject = "every tab in this window"

    @State private var isChoosingPicture = false
    @State private var pictureProblem: String?
    @State private var isDropTargeted = false
    @State private var thumbnail: CGImage?

    /// The defaults, which a row follows until the window sets its own: nothing new drawn.
    private static let none = TerminalLookStyle()
    private static let source = "None"

    var body: some View {
        let style = TerminalLookStyle.resolved(settings)
        Section {
            GlassSettingLabeled("Start From") {
                Menu("Choose a Look") {
                    ForEach(TerminalLookPreset.allCases) { preset in
                        Button(preset.title) { settings = preset.applied(to: settings) }
                    }
                }
                .fixedSize()
                .accessibilityIdentifier("terminal-window-look-preset")
            }
            GlassWindowSettingRow(TerminalWindowSettings.backdrop, overrides: $settings,
                                  global: Self.none.backdrop, inheritsFrom: Self.source) { value in
                GlassSettingLabeled(TerminalWindowSettings.backdrop.title) {
                    Picker(TerminalWindowSettings.backdrop.title, selection: value) {
                        ForEach(TerminalBackdropStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("terminal-window-backdrop")
                }
            }
            if style.backdrop == .picture {
                pictureWell(style)
                slider(TerminalWindowSettings.backdropBlur, global: Self.none.blur,
                       leading: "Sharp", trailing: "Soft", identifier: "terminal-window-backdrop-blur")
                slider(TerminalWindowSettings.backdropPixelate, global: Self.none.pixelate,
                       leading: "Smooth", trailing: "Blocky", identifier: "terminal-window-backdrop-pixelate")
                slider(TerminalWindowSettings.backdropTone, global: Self.none.tone,
                       leading: "Its own colors", trailing: "The theme's colors", identifier: "terminal-window-backdrop-tone")
            }
            if style.backdrop != .none {
                slider(TerminalWindowSettings.backdropIntensity, global: Self.none.intensity,
                       leading: "Faint", trailing: "Strong", identifier: "terminal-window-backdrop-intensity")
                if style.backdrop.quickensWithOutput {
                    GlassWindowSettingRow(TerminalWindowSettings.backdropFollowsOutput, overrides: $settings,
                                          global: Self.none.followsOutput, inheritsFrom: Self.source) { value in
                        GlassSettingLabeled(TerminalWindowSettings.backdropFollowsOutput.title) {
                            Toggle(TerminalWindowSettings.backdropFollowsOutput.title, isOn: value)
                                .accessibilityIdentifier("terminal-window-backdrop-follows-output")
                        }
                    }
                }
                slider(TerminalWindowSettings.readability, global: Self.none.readability,
                       leading: "Less scrim", trailing: "More scrim", identifier: "terminal-window-readability")
            }
        } header: {
            Text("Look")
        } footer: {
            Text("Drawn behind the text of \(subject). Coding Agent shows the agent each terminal is running, moving while it works and glowing while it waits for you. Readability darkens it under the text, and more where the text would be hard to read. Moving backgrounds stay still with Reduce Motion or Low Power Mode.")
        }

        Section {
            GlassWindowSettingRow(TerminalWindowSettings.phosphor, overrides: $settings,
                                  global: Self.none.phosphor, inheritsFrom: Self.source) { value in
                GlassSettingLabeled(TerminalWindowSettings.phosphor.title) {
                    Picker(TerminalWindowSettings.phosphor.title, selection: value) {
                        ForEach(TerminalPhosphor.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("terminal-window-phosphor")
                }
            }
            slider(TerminalWindowSettings.glow, global: Self.none.glow,
                   leading: "No glow", trailing: "Strong glow", identifier: "terminal-window-glow")
            if style.glow > 0 {
                GlassWindowSettingRow(TerminalWindowSettings.glowColor, overrides: $settings,
                                      global: Self.none.glowColor, inheritsFrom: Self.source) { value in
                    GlassSettingLabeled(TerminalWindowSettings.glowColor.title) {
                        Picker(TerminalWindowSettings.glowColor.title, selection: value) {
                            ForEach(TerminalGlowColor.allCases) { Text($0.title).tag($0) }
                        }
                        .accessibilityIdentifier("terminal-window-glow-color")
                    }
                }
            }
        } header: {
            Text("Text")
        }
    }

    private func slider(_ setting: GlassWindowSetting<Double>, global: Double, leading: String, trailing: String,
                        identifier: String) -> some View {
        GlassWindowSettingRow(setting, overrides: $settings, global: global, inheritsFrom: Self.source) { value in
            GlassSettingSlider(title: setting.title, value: value, detents: [0, 0.5, 1],
                               leadingAccessibilityLabel: leading, trailingAccessibilityLabel: trailing,
                               accessibilityIdentifier: identifier)
        }
    }

    // MARK: - The picture

    private func pictureWell(_ style: TerminalLookStyle) -> some View {
        GlassSettingLabeled(TerminalWindowSettings.backdropPicture.title) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                          style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: thumbnail == nil ? [4] : []))
                        if let thumbnail {
                            Image(decorative: thumbnail, scale: 1)
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .padding(1)
                        } else {
                            Text("Drop a picture")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 112, height: 70)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(thumbnail == nil ? "No picture" : "The window's picture")
                    .accessibilityIdentifier("terminal-window-backdrop-picture")
                    .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                        receive(providers)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Choose…") { isChoosingPicture = true }
                            .accessibilityIdentifier("terminal-window-backdrop-choose")
                        if style.picture != nil {
                            Button("Remove", role: .destructive) {
                                settings[TerminalWindowSettings.backdropPicture] = nil
                            }
                            .accessibilityIdentifier("terminal-window-backdrop-remove")
                        }
                    }
                }
                if let pictureProblem {
                    Text(pictureProblem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .fileImporter(isPresented: $isChoosingPicture, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            keep(try? Data(contentsOf: url))
        }
        .task(id: style.picture) {
            guard let name = style.picture else { thumbnail = nil; return }
            thumbnail = await TerminalBackdropPicture.load(name)?.image
        }
    }

    private func receive(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                Task { @MainActor in keep(data) }
            }
            return true
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            let data = url.flatMap { try? Data(contentsOf: $0) }
            Task { @MainActor in keep(data) }
        }
        return true
    }

    /// Keeps `data` as the window's picture, and shows the picture background.
    private func keep(_ data: Data?) {
        guard let data else {
            pictureProblem = TerminalBackgroundPictures.ImportError.notAPicture.errorDescription
            return
        }
        // Decoded and scaled off the main thread: a large photo takes a moment.
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try TerminalBackgroundPictures.importPicture(data) }
            }.value
            switch result {
            case .success(let name):
                pictureProblem = nil
                settings[TerminalWindowSettings.backdropPicture] = name
                settings[TerminalWindowSettings.backdrop] = .picture
            case .failure(let error):
                pictureProblem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
