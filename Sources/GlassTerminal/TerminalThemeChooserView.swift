//
//  TerminalThemeChooserView.swift
//  Glass Power Tools — GlassTerminal
//
//  Choose Theme (2026-10-28, a user's folder of 148 Terminal color schemes: "Let's make these work,
//  first class style!"): your themes and the schemes in iCloud Drive ▸ Glass Power Tools ▸ Terminal
//  Themes, each drawn small in its own colors — background, text, a highlighted word and its sixteen
//  — to choose for All Terminals at a glance. Import brings in Terminal profiles, or a folder of
//  them, on any device; a scheme can be copied into your themes to change its colors, or deleted
//  from every device.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A macOS Terminal profile: Terminal declares it on a Mac, and this app (Info.plist) elsewhere.
    static let terminalProfile = UTType(importedAs: "com.apple.terminal.settings", conformingTo: .data)
}

struct TerminalThemeChooserView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss
    private let schemes = TerminalSchemeLibrary.shared
    @State private var search = ""
    @State private var importing = false
    @State private var report: ImportReport?
    @State private var pendingDeletion: TerminalScheme?

    private struct ImportReport: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your Themes") {
                    ForEach(yourThemes) { record in
                        Button {
                            settingsManager.chooseTheme(record.id)
                        } label: {
                            row(name: record.theme.name, theme: record.theme,
                                chosen: settingsManager.terminalScheme == nil && record.id == settingsManager.selectedThemeID)
                        }
                        .accessibilityIdentifier("terminal-theme-\(record.theme.name)")
                    }
                }
                Section {
                    if schemes.schemes.isEmpty {
                        Text("None yet. Import Terminal profiles — .terminal files, or a folder of them — to choose from them here on every device.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(yourSchemes) { scheme in
                        Button {
                            if scheme.theme != nil { settingsManager.chooseScheme(scheme.id) }
                        } label: {
                            schemeRow(scheme)
                        }
                        .disabled(scheme.theme == nil)
                        .accessibilityIdentifier("terminal-scheme-\(scheme.name)")
                        .contextMenu {
                            Button("Copy to Your Themes", systemImage: "paintpalette") {
                                settingsManager.copyScheme(scheme)
                            }
                            .disabled(scheme.theme == nil)
                            Button("Delete…", systemImage: "trash", role: .destructive) {
                                pendingDeletion = scheme
                            }
                        }
                    }
                } header: {
                    Text(schemes.schemes.isEmpty ? "Terminal Themes" : "Terminal Themes (\(schemes.schemes.count))")
                } footer: {
                    Text(folderFooter)
                }
            }
            .searchable(text: $search, prompt: "Search themes")
            .navigationTitle("Choose Theme")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("terminal-theme-chooser-done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import…", systemImage: "square.and.arrow.down") { importing = true }
                        .accessibilityIdentifier("terminal-theme-import")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.terminalProfile, .folder],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await add(urls) }
                case .failure(let error): report = ImportReport(title: "Nothing Was Imported", message: error.localizedDescription)
                }
            }
            .alert(item: $report) { report in
                Alert(title: Text(report.title), message: Text(report.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog("Delete “\(pendingDeletion?.name ?? "")”?", isPresented: deletionPresented, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let pendingDeletion { schemes.remove(pendingDeletion) }
                    pendingDeletion = nil
                }
            } message: {
                Text("It's removed from Terminal Themes in iCloud Drive, on every device. A window that uses it goes back to All Terminals' theme.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
        .onAppear { schemes.start() }
    }

    // MARK: - Rows

    private func schemeRow(_ scheme: TerminalScheme) -> some View {
        let chosen = settingsManager.terminalScheme == scheme.id
        return HStack(spacing: 12) {
            if let theme = scheme.theme {
                TerminalThemeSample(theme: theme)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: TerminalThemeSample.width, height: TerminalThemeSample.height)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(scheme.name)
                    .foregroundStyle(.primary)
                if let problem = scheme.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !scheme.isDownloaded || scheme.theme == nil {
                    Text("Downloading from iCloud…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if chosen {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(chosen ? "Chosen" : "")
    }

    private func row(name: String, theme: TerminalTheme, chosen: Bool) -> some View {
        HStack(spacing: 12) {
            TerminalThemeSample(theme: theme)
            Text(name)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if chosen {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(chosen ? "Chosen" : "")
    }

    // MARK: - What's shown

    private var yourThemes: [TerminalThemeRecord] {
        settingsManager.themeLibrary.activeRecords.filter { matches($0.theme.name) }
    }

    private var yourSchemes: [TerminalScheme] {
        schemes.schemes.filter { matches($0.name) }
    }

    private func matches(_ name: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || name.localizedStandardContains(query)
    }

    private var folderFooter: String {
        switch schemes.storage {
        case .iCloud:
            "In iCloud Drive ▸ Glass Power Tools ▸ Terminal Themes, on every device: add .terminal files there in Files or the Finder, or here. Each brings its colors, background included; your font stays."
        case .device:
            "On this device only: iCloud Drive is off, or the app can't reach it. Each brings its colors, background included; your font stays."
        case .finding:
            "Looking for Terminal Themes in iCloud Drive…"
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    // MARK: - Importing

    private func add(_ urls: [URL]) async {
        let outcome = await schemes.add(urls)
        let added = outcome.added.count
        guard !outcome.problems.isEmpty else {
            if added == 1, let name = outcome.added.first {
                // One file: it is the one wanted, so it is chosen.
                let id = TerminalSchemeFiles.id(forFileNamed: name)
                if schemes.scheme(withID: id) != nil { settingsManager.chooseScheme(id) }
            }
            return
        }
        let listed = outcome.problems.prefix(8).map { "\($0.name): \($0.problem)" }.joined(separator: "\n")
        let more = outcome.problems.count > 8 ? "\n…and \(outcome.problems.count - 8) more." : ""
        report = ImportReport(
            title: added == 0 ? "Nothing Was Imported" : "\(added) Imported, \(outcome.problems.count) Not",
            message: listed + more)
    }
}

/// A theme drawn small in its own colors: its background, a prompt in its text, a word highlighted
/// as a selection, and its sixteen colors. Decoration: the row says its name.
struct TerminalThemeSample: View {
    let theme: TerminalTheme
    static let width: CGFloat = 112
    static let height: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("~ % ").foregroundStyle(theme.foreground.color)
                Text("ls ").foregroundStyle(theme.green.color)
                Text("main")
                    .foregroundStyle(theme.foreground.color)
                    .background(theme.selection.color)
            }
            .font(.system(size: 10, design: .monospaced))
            .lineLimit(1)
            ForEach([0, 8], id: \.self) { start in
                HStack(spacing: 2) {
                    ForEach(start..<start + 8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(theme.ansiColors[index].color)
                            .frame(width: 10, height: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(width: Self.width, height: Self.height, alignment: .leading)
        .background(theme.canvasBackgroundColor.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
