//
//  SettingsView.swift
//  glas.sh
//
//  Application settings
//

import SwiftUI
import GlassLayers
import GlassShell
import GlassSSHTransport
import UniformTypeIdentifiers
import GlasSecretStore
import GlassTerminalEmulator
#if os(macOS)
import UniformTypeIdentifiers
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SessionManager.self) private var sessionManager
    private var serverManager: ServerManager { sessionManager.serverManager }
    @State private var sshConfigText: String = ""
    @State private var importResultMessage: String?
    @State private var tailscaleAuthMethod: TailscaleAuthMethod = .apiKey
    @State private var persistedTailscaleAuthMethod: TailscaleAuthMethod = .apiKey
    @State private var tailscaleCredentialPresence: TailscaleCredentialPresence = .absent
    @State private var tailscaleAPIKey: String = ""
    @State private var tailscaleOAuthClientID: String = ""
    @State private var tailscaleOAuthClientSecret: String = ""
    @State private var tailscaleTestResult: String?
    @State private var tailscaleTestInProgress = false
    #if os(macOS)
    #endif
    
    var body: some View {
        @Bindable var settings = settingsManager
        
        Form {
            Section("Connection") {
                Toggle("Auto-reconnect on disconnect", isOn: $settings.autoReconnect)
                    .onChange(of: settings.autoReconnect) { _, _ in
                        settings.saveSettings()
                    }
                
                Toggle("Confirm before closing active sessions", isOn: $settings.confirmBeforeClosing)
                    .onChange(of: settings.confirmBeforeClosing) { _, _ in
                        settings.saveSettings()
                    }
            }
            

            Section("Terminal Behavior") {
                Toggle("Keep scrollback during session", isOn: $settings.saveScrollback)
                    .onChange(of: settings.saveScrollback) { _, _ in
                        settings.saveSettings()
                    }

                Text("Scrollback stays in memory and is cleared when the terminal session ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Suggest fixes for errors", isOn: $settings.errorSuggestions)
                    .onChange(of: settings.errorSuggestions) { _, _ in
                        settings.saveSettings()
                    }
                Text("When a terminal's output shows an error, Apple Intelligence on this device explains it and offers a fix to review. Pause it in one terminal from the suggestion itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Stepper("Max scrollback lines: \(settings.maxScrollbackLines)",
                       value: $settings.maxScrollbackLines,
                       in: 1000...100000,
                       step: 1000)
                    .onChange(of: settings.maxScrollbackLines) { _, _ in
                        settings.saveSettings()
                    }
            }
            
            #if os(macOS)
            Section("Local Terminal") {
                TextField("Shell (default: login shell)", text: $settings.localShell)
                    .onChange(of: settings.localShell) { _, _ in settings.saveSettings() }
                TextField("Working directory (default: home)", text: $settings.localWorkingDirectory)
                    .onChange(of: settings.localWorkingDirectory) { _, _ in settings.saveSettings() }
                Text("Use an absolute path or ~. Changes apply to new terminals. Saved Workgroups can override these defaults. Whether they run in tmux is under Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section("Session Recording") {
                let recordings = SessionRecorder.loadRecordings()
                let totalSize = Self.recordingStorageSize()
                LabeledContent("Recordings", value: "\(recordings.count)")
                LabeledContent("Storage", value: Self.formatBytes(totalSize))
            }

            Section("Notifications") {
                Toggle("Bell enabled", isOn: $settings.bellEnabled)
                    .onChange(of: settings.bellEnabled) { _, _ in
                        settings.saveSettings()
                    }
                
                Toggle("Visual bell", isOn: $settings.visualBell)
                    .disabled(!settings.bellEnabled)
                    .onChange(of: settings.visualBell) { _, _ in
                        settings.saveSettings()
                    }
            }

            Section("Security") {
                Picker("Host key verification", selection: $settings.hostKeyVerificationMode) {
                    ForEach([HostKeyVerificationMode.ask, .strict], id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .onChange(of: settings.hostKeyVerificationMode) { _, _ in
                    settings.saveSettings()
                }
            }

            TrustedHostKeysSection()

            Section("Tailscale") {
                TextField("Tailnet name", text: $settings.tailscaleTailnet)
                    .terminalTextInputDefaults()
                    .onChange(of: settings.tailscaleTailnet) { _, _ in
                        settings.saveSettings()
                    }

                Picker("Auth method", selection: $tailscaleAuthMethod) {
                    Text("API Key").tag(TailscaleAuthMethod.apiKey)
                    Text("OAuth Client").tag(TailscaleAuthMethod.oauthClient)
                }
                .onChange(of: tailscaleAuthMethod) { _, _ in
                    tailscaleTestResult = nil
                    clearTailscaleCredentialInputs()
                }

                if tailscaleAuthMethod == .apiKey {
                    SecureField("API Key", text: $tailscaleAPIKey)
                        .textContentType(.init(rawValue: ""))
                    Text("Generate at admin console → Settings → Keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("OAuth Client ID", text: $tailscaleOAuthClientID)
                        .terminalTextInputDefaults()
                    SecureField("OAuth Client Secret", text: $tailscaleOAuthClientSecret)
                        .textContentType(.init(rawValue: ""))
                    Text("Create at admin console → Settings → OAuth clients")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(tailscaleCredentialStatusText, systemImage: tailscaleCredentialStatusIcon)
                    .font(.caption)
                    .foregroundStyle(tailscaleCredentialStatusColor)

                Button {
                    saveTailscaleCredentialsAndTest()
                } label: {
                    HStack {
                        if tailscaleTestInProgress {
                            ProgressView().controlSize(.small)
                        }
                        Text("Save & Test")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tailscaleTestInProgress || !tailscaleCredentialsValid)

                if let tailscaleTestResult {
                    Text(tailscaleTestResult)
                        .font(.caption)
                        .foregroundStyle(tailscaleTestResult.hasPrefix("Connected") ? .green : .red)
                }

                Text("Earlier-build Tailscale credentials are not imported from unnamespaced entries in the shared Keychain service. If a field is empty after updating, re-enter it once to store it in the terminal's own namespace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // **Moved to the library, under Keys** (D26 stage 4). A key is workspace-level: it
            // can authenticate a terminal on one machine and a database on another, so it is
            // managed where every machine and service can be seen at once — which is also the
            // only place that can say what deleting one would unassign. This line stays because
            // this is where the manager used to be.
            Section("SSH Keys") {
                LabeledContent("Keys", value: "\(settings.sshKeys.count)")
                Text("SSH keys are managed in the library, under Keys, where each one shows its fingerprint, whether it can leave this device, and which services use it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Import SSH Config") {
                Text("Imports explicit Host entries. Match, Include, wildcard defaults, and unsupported options are reported for review. IdentityFile must match a key already in the library's Keys panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $sshConfigText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)

                Button("Import into Server Configs") {
                    Task { @MainActor in
                        let result = await settings.importSSHConfig(sshConfigText, serverManager: serverManager)
                        let warnings = result.warnings.joined(separator: "\n")
                        importResultMessage =
                            "Imported: \(result.imported), Updated: \(result.updated), Skipped: \(result.skipped)"
                            + (warnings.isEmpty ? "" : "\n\nWarnings:\n\(warnings)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sshConfigText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let importResultMessage, !importResultMessage.isEmpty {
                    Text(importResultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        // No extra padding: a grouped form brings its own margins, and a second set made these
        // pages sit inset from the shell's in the Mac's Settings window (2026-09-25).
        .task {
            serverManager.loadServersIfNeeded()
            await loadTailscaleCredentialState()
        }
        .onDisappear {
            clearTailscaleCredentialInputs()
        }
    }

    private func loadTailscaleCredentialState() async {
        let storedMethod = TailscaleAuthMethod(rawValue:
            GlassUITestRun.settingsDefaults.string(forKey: UserDefaultsKeys.tailscaleAuthMethod) ?? "apiKey"
        ) ?? .apiKey
        persistedTailscaleAuthMethod = storedMethod
        tailscaleAuthMethod = storedMethod
        tailscaleCredentialPresence = await TailscaleClient.storedCredentialPresence()
        clearTailscaleCredentialInputs()
    }

    private var tailscaleCredentialsValid: Bool {
        switch tailscaleAuthMethod {
        case .apiKey:
            let replacement = tailscaleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return !replacement.isEmpty || selectedTailscaleCredentialIsConfigured
        case .oauthClient:
            let clientID = tailscaleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientSecret = tailscaleOAuthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if clientID.isEmpty, clientSecret.isEmpty {
                return selectedTailscaleCredentialIsConfigured
            }
            return !clientID.isEmpty && !clientSecret.isEmpty
        }
    }

    private var selectedTailscaleCredentialIsConfigured: Bool {
        tailscaleAuthMethod == persistedTailscaleAuthMethod
            && tailscaleCredentialPresence == .configured
    }

    private var tailscaleCredentialStatusText: String {
        guard tailscaleAuthMethod == persistedTailscaleAuthMethod else {
            return "Enter replacement credentials to switch authentication methods."
        }
        switch tailscaleCredentialPresence {
        case .configured:
            return "Credentials are configured. Leave the replacement fields empty to test them."
        case .absent:
            return "No credentials are configured."
        case .unavailable:
            return "Credential status is unavailable. Check Keychain access before replacing credentials."
        }
    }

    private var tailscaleCredentialStatusIcon: String {
        switch tailscaleAuthMethod == persistedTailscaleAuthMethod
            ? tailscaleCredentialPresence
            : .absent {
        case .configured: return "checkmark.circle"
        case .absent: return "key"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    private var tailscaleCredentialStatusColor: Color {
        guard tailscaleAuthMethod == persistedTailscaleAuthMethod else { return .secondary }
        switch tailscaleCredentialPresence {
        case .configured: return .green
        case .absent: return .secondary
        case .unavailable: return .orange
        }
    }

    private func clearTailscaleCredentialInputs() {
        tailscaleAPIKey = ""
        tailscaleOAuthClientID = ""
        tailscaleOAuthClientSecret = ""
    }

    private static func recordingStorageSize() -> Int64 {
        let directory = SessionRecorder.recordingsDirectory
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func saveTailscaleCredentialsAndTest() {
        tailscaleTestInProgress = true
        tailscaleTestResult = nil

        do {
            let wroteReplacement: Bool
            switch tailscaleAuthMethod {
            case .apiKey:
                let apiKey = tailscaleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if apiKey.isEmpty {
                    guard selectedTailscaleCredentialIsConfigured else {
                        throw TailscaleError.notAuthenticated
                    }
                    wroteReplacement = false
                } else {
                    try KeychainManager.saveTailscaleAPIKey(apiKey)
                    wroteReplacement = true
                }
            case .oauthClient:
                let clientID = tailscaleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
                let clientSecret = tailscaleOAuthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                if clientID.isEmpty, clientSecret.isEmpty {
                    guard selectedTailscaleCredentialIsConfigured else {
                        throw TailscaleError.notAuthenticated
                    }
                    wroteReplacement = false
                } else {
                    guard !clientID.isEmpty, !clientSecret.isEmpty else {
                        throw TailscaleError.notAuthenticated
                    }
                    try KeychainManager.saveTailscaleOAuthCredentials(
                        clientID: clientID,
                        clientSecret: clientSecret
                    )
                    wroteReplacement = true
                }
            }
            if wroteReplacement {
                // Switch the active method only after its credential write succeeds.
                GlassUITestRun.settingsDefaults.set(tailscaleAuthMethod.rawValue, forKey: UserDefaultsKeys.tailscaleAuthMethod)
                persistedTailscaleAuthMethod = tailscaleAuthMethod
                NotificationCenter.default.post(name: .tailscaleCredentialsDidChange, object: nil)
            }
            clearTailscaleCredentialInputs()
            tailscaleCredentialPresence = TailscaleClient.credentialPresence()
        } catch {
            tailscaleTestResult = "Failed to save: \(error.localizedDescription)"
            clearTailscaleCredentialInputs()
            tailscaleTestInProgress = false
            return
        }

        Task {
            let client = TailscaleClient()
            do {
                let success = try await client.testConnection()
                tailscaleTestResult = success ? "Connected to Tailscale." : "Connection test failed."
            } catch {
                tailscaleTestResult = "Error: \(error.localizedDescription)"
            }
            tailscaleCredentialPresence = TailscaleClient.credentialPresence()
            clearTailscaleCredentialInputs()
            tailscaleTestInProgress = false
        }
    }
}

// MARK: - Terminal Settings

struct TerminalSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var showingThemeEditor = false
    @State private var showingThemeChooser = false
    
    var body: some View {
        @Bindable var settings = settingsManager
        let theme = settingsManager.allTerminalsTheme
        
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(theme.name)
                            .font(.headline)
                            .accessibilityIdentifier("terminal-settings-theme-name")
                        
                        Text("Font: \(theme.fontName) \(Int(theme.fontSize))pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Two buttons in one row: each its own, or a tap on either presses both.
                    Button("Choose…") {
                        showingThemeChooser = true
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("terminal-settings-choose-theme")
                    Button("Edit Theme") {
                        showingThemeEditor = true
                    }
                    .buttonStyle(.borderless)
                }
                
                // Color preview
                LazyVGrid(columns: previewColumns, spacing: 12) {
                    ForEach([
                        ("Background", theme.background.color),
                        ("Foreground", theme.foreground.color),
                        ("Selection", theme.selection.color),
                        ("Red", theme.red.color),
                        ("Green", theme.green.color),
                        ("Blue", theme.blue.color),
                        ("Yellow", theme.yellow.color)
                    ], id: \.0) { name, color in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                                }

                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(name) color preview")
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                if settingsManager.terminalScheme != nil {
                    Text(settingsManager.allTerminalsTheme.id == settingsManager.terminalScheme
                         ? "From Terminal Themes in iCloud Drive. To change its colors, copy it to your themes in Choose, then edit it."
                         : "The scheme All Terminals use isn't on this device yet, so they use your theme until it arrives.")
                }
            }
            
            Section("Canvas") {
                // Interactive Glass is no longer offered: it was a Vision Pro toggle, and it changes
                // nothing there since the window draws Apple's glass itself (D59). The stored value
                // stays, so earlier builds and other devices still read it.
                GlassTintPicker(value: $settings.glassTint)
                    .onChange(of: settings.glassTint) { _, _ in
                        settings.saveSettings()
                    }
                Text("These change every terminal window. To change one window — its glass, tint, theme, font, cursor, bell or scrollback — open Settings from its tools menu and choose This Window. \(Self.sharedGlassSettings) are shared with every Glass window: change them in Appearance. Tint applies only to the terminal canvas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Font") {
                Picker("Font Family", selection: fontFamilyBinding) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Monaco").tag("Monaco")
                    Text("Menlo").tag("Menlo")
                    Text("Courier New").tag("Courier New")
                }
                
                Slider(value: fontSizeBinding,
                       in: Double(TerminalTheme.minimumFontSize)...Double(TerminalTheme.maximumFontSize),
                       step: 1) {
                    Text("Font Size")
                } minimumValueLabel: {
                    Text("\(Int(TerminalTheme.minimumFontSize))")
                } maximumValueLabel: {
                    Text("\(Int(TerminalTheme.maximumFontSize))")
                }

                // A Mac has no system text size to follow.
                #if !os(macOS)
                Toggle("Scale with System Text Size", isOn: $settings.fontFollowsSystemTextSize)
                    .onChange(of: settings.fontFollowsSystemTextSize) { _, _ in
                        settings.saveSettings()
                    }
                    .accessibilityIdentifier("terminal-settings-follows-text-size")
                Text("Font Size is the size at the standard text size, and a larger text size in Settings makes it larger. On this device only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }

            Section("Initial Terminal Size") {
                Stepper(
                    value: $settings.initialTerminalColumns,
                    in: TerminalGeometry.columnRange,
                    step: 5
                ) {
                    LabeledContent("Columns", value: "\(settings.initialTerminalColumns)")
                }
                .onChange(of: settings.initialTerminalColumns) { _, _ in
                    settings.saveSettings()
                }

                Stepper(
                    value: $settings.initialTerminalRows,
                    in: TerminalGeometry.rowRange
                ) {
                    LabeledContent("Rows", value: "\(settings.initialTerminalRows)")
                }
                .onChange(of: settings.initialTerminalRows) { _, _ in
                    settings.saveSettings()
                }

                Text("Used as the app-wide PTY fallback. When a terminal is visible, its measured window size takes precedence before the remote shell starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // D75 (2026-10-16): "I may want a 120 x 40 terminal, but with a much smaller window."
            if TerminalResizeBehavior.isOffered {
                Section {
                    Picker("When a window is resized", selection: $settings.whenResized) {
                        ForEach(TerminalResizeBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .onChange(of: settings.whenResized) { _, _ in
                        settings.saveSettings()
                    }
                    .accessibilityIdentifier("terminal-settings-when-resized")
                } header: {
                    Text("Resizing")
                } footer: {
                    Text("Change Rows and Columns: a smaller window holds fewer, and the program redraws to fit. Scale the Text: the terminal keeps the rows and columns it has, and its text grows and shrinks with the window, which keeps their shape. Scale Text in a window's bar switches that window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Cursor") {
                Picker("Cursor Style", selection: $settings.cursorStyle) {
                    Text("Block").tag("Block")
                    Text("Underline").tag("Underline")
                    Text("Bar").tag("Bar")
                }
                .onChange(of: settings.cursorStyle) { _, _ in
                    settings.saveSettings()
                }
                
                Toggle("Blinking cursor", isOn: $settings.blinkingCursor)
                    .onChange(of: settings.blinkingCursor) { _, _ in
                        settings.saveSettings()
                    }
            }

            #if os(macOS) || os(visionOS)
            // The file a printed path names, over the terminal (2026-10-16: "Show previews:
            // ( ) Never (•) Mouseover ( ) Mouseover + space"; on the headset too, 2026-10-22).
            // Quick Look on a path's menu shows it whatever this says.
            Section {
                Picker("Show previews", selection: $settings.pathPreviews) {
                    ForEach(TerminalPathPreviews.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #endif
                .onChange(of: settings.pathPreviews) { _, _ in
                    settings.saveSettings()
                }
                .accessibilityIdentifier("terminal-settings-path-previews")
            } header: {
                Text("Previews")
            } footer: {
                #if os(macOS)
                Text("A file whose path a terminal printed — a picture, a PDF, Markdown, code — shown over the terminal, from this Mac or the server. Mouseover shows it when the pointer rests on the path. With Mouseover + Space, Space shows it instead, and on a web address asks to open it. Quick Look in a path's right-click menu shows it either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                Text("A file whose path a terminal printed — a picture, a PDF, Markdown, code — shown over the terminal, from the server. Mouseover shows it when a trackpad's or mouse's pointer rests on the path; your eyes can't, as visionOS doesn't tell apps where you look. With Mouseover + Space, Space shows it instead. Quick Look in a path's pinch-and-hold menu shows it either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            #endif

            #if os(visionOS)
            // Focus Mode's surroundings (2026-10-26), for every window; This Window for one.
            FocusEnvironmentLibrarySection(chosen: $settings.focusEnvironment,
                                           opensImmersed: $settings.focusOpensImmersed,
                                           soundLevel: $settings.focusEnvironmentSound)
                .onChange(of: settings.focusEnvironment) { _, _ in
                    settings.saveSettings()
                }
                .onChange(of: settings.focusOpensImmersed) { _, _ in
                    settings.saveSettings()
                }
                .onChange(of: settings.focusEnvironmentSound) { _, _ in
                    settings.saveSettings()
                }
            #endif

            #if os(macOS)
            MacLocalTerminalServerSection(settings: settingsManager)
            #endif
        }
        .formStyle(.grouped)
        // No extra padding: a grouped form brings its own margins, and a second set made these
        // pages sit inset from the shell's in the Mac's Settings window (2026-09-25).
        .sheet(isPresented: $showingThemeChooser) {
            TerminalThemeChooserView()
        }
        .sheet(isPresented: $showingThemeEditor) {
            ThemeEditorView()
                .environment(settingsManager)
        }
    }

    /// Appearance's settings this device offers, as the Canvas footer names them: no Material on
    /// Vision Pro, where every window's glass is Apple's own.
    private static var sharedGlassSettings: String {
        #if os(visionOS)
        "Opacity and Glass"
        #else
        "Opacity, Glass and Material"
        #endif
    }

    private var previewColumns: [GridItem] {
        #if os(iOS)
        [GridItem(.adaptive(minimum: 84), spacing: 8)]
        #else
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
        #endif
    }

    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { settingsManager.currentTheme.fontName },
            set: { newValue in
                var theme = settingsManager.currentTheme
                theme.fontName = newValue
                settingsManager.saveTheme(theme)
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settingsManager.currentTheme.fontSize) },
            set: { newValue in
                var theme = settingsManager.currentTheme
                theme.fontSize = CGFloat(newValue)
                settingsManager.saveTheme(theme)
            }
        )
    }
}

// MARK: - Snippets Settings

struct SnippetsSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var showingAddSnippet = false
    @State private var editingSnippet: CommandSnippet?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Command Snippets")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showingAddSnippet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Snippets list
            if settingsManager.snippets.isEmpty {
                ContentUnavailableView {
                    Label("No Snippets", systemImage: "text.badge.star")
                } description: {
                    Text("Create command snippets for quick access")
                } actions: {
                    Button {
                        showingAddSnippet = true
                    } label: {
                        Text("Add Snippet")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(settingsManager.snippets) { snippet in
                        SnippetRow(snippet: snippet) {
                            editingSnippet = snippet
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            settingsManager.deleteSnippet(settingsManager.snippets[index])
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSnippet) {
            AddSnippetView(settingsManager: settingsManager)
        }
        .sheet(item: $editingSnippet) { snippet in
            EditSnippetView(snippet: snippet, settingsManager: settingsManager)
        }
    }
}

// MARK: - Snippet Row

struct SnippetRow: View {
    let snippet: CommandSnippet
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.name)
                    .font(.headline)
                
                Text(snippet.command)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if !snippet.description.isEmpty {
                    Text(snippet.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                if let lastUsed = snippet.lastUsed {
                    HStack(spacing: 4) {
                        Text("Used \(snippet.useCount) times")
                        Text("•")
                        Text("Last: \(lastUsed, formatter: relativeDateFormatter)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                }
            }
            
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add/Edit Snippet Views

struct AddSnippetView: View {
    @Bindable var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var command = ""
    @State private var description = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    
                    TextField("Command", text: $command, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3...6)
                    
                    TextField("Description (optional)", text: $description)
                }
                
                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag) {
                                tags.removeAll { $0 == tag }
                            }
                        }
                        
                        HStack(spacing: 4) {
                            TextField("Add tag", text: $newTag)
                                .textFieldStyle(.plain)
                                .frame(width: 80)
                                .onSubmit {
                                    if !newTag.isEmpty {
                                        tags.append(newTag)
                                        newTag = ""
                                    }
                                }
                            
                            if !newTag.isEmpty {
                                Button {
                                    tags.append(newTag)
                                    newTag = ""
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add tag")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .capsule)
                    }
                }
            }
            .navigationTitle("Add Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let snippet = CommandSnippet(
                            name: name,
                            command: command,
                            description: description,
                            tags: tags
                        )
                        settingsManager.addSnippet(snippet)
                        dismiss()
                    }
                    .disabled(name.isEmpty || command.isEmpty)
                }
            }
        }
    }
}

struct EditSnippetView: View {
    let snippet: CommandSnippet
    @Bindable var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var command: String
    @State private var description: String
    @State private var tags: [String]
    @State private var newTag = ""
    
    init(snippet: CommandSnippet, settingsManager: SettingsManager) {
        self.snippet = snippet
        self.settingsManager = settingsManager
        
        _name = State(initialValue: snippet.name)
        _command = State(initialValue: snippet.command)
        _description = State(initialValue: snippet.description)
        _tags = State(initialValue: snippet.tags)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    
                    TextField("Command", text: $command, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3...6)
                    
                    TextField("Description (optional)", text: $description)
                }
                
                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag) {
                                tags.removeAll { $0 == tag }
                            }
                        }
                        
                        HStack(spacing: 4) {
                            TextField("Add tag", text: $newTag)
                                .textFieldStyle(.plain)
                                .frame(width: 80)
                                .onSubmit {
                                    if !newTag.isEmpty {
                                        tags.append(newTag)
                                        newTag = ""
                                    }
                                }
                            
                            if !newTag.isEmpty {
                                Button {
                                    tags.append(newTag)
                                    newTag = ""
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add tag")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .capsule)
                    }
                }

                Section("Statistics") {
                    LabeledContent("Times used", value: "\(snippet.useCount)")
                    if let lastUsed = snippet.lastUsed {
                        LabeledContent("Last used", value: lastUsed, format: .dateTime)
                    }
                }
            }
            .navigationTitle("Edit Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updatedSnippet = snippet
                        updatedSnippet.name = name
                        updatedSnippet.command = command
                        updatedSnippet.description = description
                        updatedSnippet.tags = tags
                        
                        settingsManager.updateSnippet(updatedSnippet)
                        dismiss()
                    }
                    .disabled(name.isEmpty || command.isEmpty)
                }
            }
        }
    }
}

// MARK: - Theme Editor

struct ThemeEditorView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var theme: TerminalTheme
    @State private var themeLibraryDraft: TerminalThemeLibrary
    @State private var selectedRecordID: UUID?
    @State private var themeImportError: String?
    @State private var themePendingDeletion: TerminalThemeRecord?

    init() {
        _theme = State(initialValue: TerminalTheme.default)
        _themeLibraryDraft = State(initialValue: .initial())
        _selectedRecordID = State(initialValue: nil)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List {
                    if let loadError = settingsManager.themeLibraryLoadError {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    ForEach(themeLibraryDraft.activeRecords) { record in
                        Button {
                            selectDraft(record.id)
                        } label: {
                            themeListRow(
                                theme: record.theme,
                                originDescription: originDescription(record.origin),
                                isActive: record.id == themeLibraryDraft.selectedThemeID,
                                isDraftSelected: record.id == selectedRecordID
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            record.id == selectedRecordID
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear
                        )
                    }
                }
                .accessibilityLabel("Terminal themes")

                Divider()

                managementActions
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                GroupBox("iCloud Sync") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Sync terminal settings", isOn: iCloudSyncBinding)
                        Text(settingsManager.iCloudSyncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        #if os(visionOS)
                        Text("Apple Terminal profiles imported on your Mac appear here after iCloud sync. Profile colors and fonts sync; Mac shell commands and window backgrounds do not.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        #endif
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("Themes")
        } detail: {
            if selectedRecordID == nil {
                ContentUnavailableView(
                    "Select a Theme",
                    systemImage: "paintpalette",
                    description: Text("Choose a terminal theme to inspect or edit.")
                )
            } else {
                Form {
                    Section("Preview") {
                        livePreview
                    }

                    Section("General") {
                        TextField("Name", text: themeNameBinding)
                            .disabled(selectedThemeIsBuiltIn)
                        Picker("Canvas Material", selection: canvasAppearanceBinding) {
                            ForEach(TerminalThemeAppearance.allCases, id: \.self) { appearance in
                                Text(appearance.displayName).tag(appearance)
                            }
                        }
                        Text("Window chrome remains native. Canvas material controls only the terminal's blur polarity so theme contrast stays stable across bright and dark surroundings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ColorPicker(
                            "Background",
                            selection: colorBinding(for: \.background),
                            supportsOpacity: false
                        )
                        ColorPicker(
                            "Foreground",
                            selection: colorBinding(for: \.foreground),
                            supportsOpacity: false
                        )
                        ColorPicker(
                            "Cursor",
                            selection: colorBinding(for: \.cursor),
                            supportsOpacity: false
                        )
                        ColorPicker("Selection", selection: colorBinding(for: \.selection))

                        Picker("Font Family", selection: $theme.fontName) {
                            if !["SF Mono", "Monaco", "Menlo", "Courier New"].contains(theme.fontName) {
                                Text(theme.fontName).tag(theme.fontName)
                            }
                            Text("SF Mono").tag("SF Mono")
                            Text("Monaco").tag("Monaco")
                            Text("Menlo").tag("Menlo")
                            Text("Courier New").tag("Courier New")
                        }

                        Slider(
                            value: fontSizeBinding,
                            in: Double(TerminalTheme.minimumFontSize)...Double(TerminalTheme.maximumFontSize),
                            step: 1
                        ) {
                            Text("Font Size")
                        } minimumValueLabel: {
                            Text("\(Int(TerminalTheme.minimumFontSize))")
                        } maximumValueLabel: {
                            Text("\(Int(TerminalTheme.maximumFontSize))")
                        }

                        Button("Use Apple Clear Dark Colors", systemImage: "paintpalette") {
                            theme.applyAppleClearDarkColors()
                        }
                    }

                    Section("ANSI Colors") {
                        ansiColorGrid
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(theme.name)
            }
        }
        .onAppear(perform: loadInitialSelection)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSelectedTheme()
                }
                .disabled(
                    settingsManager.themeLibraryLoadError != nil
                        || selectedRecordID == nil
                        || !theme.isValidForPersistence
                        || !themeLibraryDraft.activeRecords.allSatisfy({ $0.theme.isValidForPersistence })
                )
            }
        }
        .alert("Theme Import Failed", isPresented: themeImportErrorPresented) {
            Button("OK", role: .cancel) { themeImportError = nil }
        } message: {
            Text(themeImportError ?? "The selected theme could not be imported.")
        }
        .confirmationDialog(
            "Delete \(themePendingDeletion?.theme.name ?? "Theme")?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Theme", role: .destructive) {
                confirmDeleteSelectedTheme()
            }
            Button("Cancel", role: .cancel) {
                themePendingDeletion = nil
            }
        } message: {
            Text("This removes the custom theme from the library when you save your changes.")
        }
        #if os(macOS)
        .frame(minWidth: 880, minHeight: 620)
        #endif
    }

    private var managementActions: some View {
        HStack(spacing: 12) {
            Button("New", systemImage: "plus") {
                duplicateSelectedTheme(asNewTheme: true)
            }
            .disabled(selectedRecordID == nil)

            Button("Duplicate", systemImage: "plus.square.on.square") {
                duplicateSelectedTheme(asNewTheme: false)
            }
            .disabled(selectedRecordID == nil)

            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteSelectedTheme()
            }
            .disabled(selectedRecordID == nil || selectedThemeIsBuiltIn)

            Button("Reset", systemImage: "arrow.counterclockwise") {
                resetSelectedTheme()
            }
            .disabled(selectedRecordID == nil || !selectedThemeIsBuiltIn)

            #if os(macOS)
            Menu {
                Button("From .terminal File…") {
                    importThemeFromDisk()
                }
                if !appleTerminalBuiltInProfiles.isEmpty {
                    Menu("Apple Built-in Profiles") {
                        ForEach(appleTerminalBuiltInProfiles, id: \.path) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                importTheme(at: url)
                            }
                        }
                    }
                }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            #endif
        }
        #if os(macOS)
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .help("Create, duplicate, delete, reset, or import terminal themes")
        #else
        .frame(minHeight: 60)
        #endif
    }

    private func themeListRow(
        theme: TerminalTheme,
        originDescription: String,
        isActive: Bool,
        isDraftSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(theme.name)
                        .lineLimit(1)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Active")
                    }
                }
                Text(originDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                ForEach(Array(theme.ansiColors.prefix(4).enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.color)
                        .frame(width: 8, height: 22)
                }
            }
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isDraftSelected ? .isSelected : [])
        .accessibilityValue(isDraftSelected ? "Selected for editing" : originDescription)
        #if os(visionOS)
        .frame(minHeight: 60)
        #else
        .frame(minHeight: 34)
        #endif
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Aa 01")
                    .font(.custom(theme.fontName, size: max(10, theme.fontSize)))
                    .foregroundStyle(theme.foreground.color)
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.cursor.color)
                    .frame(width: 8, height: 20)
            }

            HStack(spacing: 3) {
                ForEach(Array(theme.ansiColors.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.color)
                        .frame(maxWidth: .infinity, minHeight: 14)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            livePreviewBackground
                .clipShape(.rect(cornerRadius: 10))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live preview of \(theme.name)")
    }

    @ViewBuilder
    private var livePreviewBackground: some View {
        #if os(macOS)
        TerminalCanvasBackground(
            color: theme.canvasBackgroundColor,
            tint: TerminalGlassTint.color(for: settingsManager.glassTint),
            opacity: settingsManager.windowOpacity,
            blur: settingsManager.blurBackground,
            appearance: theme.resolvedAppearance
        )
        #else
        ZStack {
            Rectangle()
                .fill(theme.canvasBackgroundColor.color)
                .opacity(settingsManager.windowOpacity)
            if let tint = TerminalGlassTint.color(for: settingsManager.glassTint) {
                Rectangle()
                    .fill(tint.opacity(TerminalCanvasTint.strength(canvasOpacity: settingsManager.windowOpacity)))
            }
        }
        .modifier(GlassWindowBackground(
            interactive: false,
            material: .regularMaterial,
            blurAmount: settingsManager.blurBackground,
            appearance: theme.resolvedAppearance
        ))
        #endif
    }

    private var ansiColorGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Normal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Bright")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ansiColorRow("Black", normal: \.black, bright: \.brightBlack)
            ansiColorRow("Red", normal: \.red, bright: \.brightRed)
            ansiColorRow("Green", normal: \.green, bright: \.brightGreen)
            ansiColorRow("Yellow", normal: \.yellow, bright: \.brightYellow)
            ansiColorRow("Blue", normal: \.blue, bright: \.brightBlue)
            ansiColorRow("Magenta", normal: \.magenta, bright: \.brightMagenta)
            ansiColorRow("Cyan", normal: \.cyan, bright: \.brightCyan)
            ansiColorRow("White", normal: \.white, bright: \.brightWhite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ansiColorRow(
        _ name: String,
        normal: WritableKeyPath<TerminalTheme, CodableColor>,
        bright: WritableKeyPath<TerminalTheme, CodableColor>
    ) -> some View {
        GridRow {
            Text(name)
            ansiColorPicker("\(name), normal", keyPath: normal)
            ansiColorPicker("\(name), bright", keyPath: bright)
        }
    }

    @ViewBuilder
    private func ansiColorPicker(
        _ label: String,
        keyPath: WritableKeyPath<TerminalTheme, CodableColor>
    ) -> some View {
        ColorPicker(
            label,
            selection: colorBinding(for: keyPath),
            supportsOpacity: false
        )
            .labelsHidden()
            .accessibilityLabel(label)
            #if os(visionOS)
            .frame(minWidth: 60, minHeight: 60)
            #endif
    }

    private func colorBinding(for keyPath: WritableKeyPath<TerminalTheme, CodableColor>) -> Binding<Color> {
        Binding(
            get: { theme[keyPath: keyPath].color },
            set: { newColor in
                theme[keyPath: keyPath] = CodableColor(color: newColor)
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(theme.fontSize) },
            set: { theme.fontSize = CGFloat($0) }
        )
    }

    private var themeNameBinding: Binding<String> {
        Binding(
            get: { theme.name },
            set: { theme.name = String($0.prefix(TerminalTheme.maximumNameLength)) }
        )
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.iCloudSyncEnabled },
            set: { settingsManager.setICloudSyncEnabled($0) }
        )
    }

    private var canvasAppearanceBinding: Binding<TerminalThemeAppearance> {
        Binding(
            get: { theme.preferredAppearance ?? .automatic },
            set: { theme.preferredAppearance = $0 }
        )
    }

    private var selectedThemeIsBuiltIn: Bool {
        guard let selectedRecordID else { return false }
        return themeLibraryDraft.activeRecords.first {
            $0.id == selectedRecordID
        }?.isBuiltIn == true
    }

    private var themeImportErrorPresented: Binding<Bool> {
        Binding(
            get: { themeImportError != nil },
            set: { if !$0 { themeImportError = nil } }
        )
    }

    private func loadInitialSelection() {
        themeLibraryDraft = settingsManager.themeLibrary
        let selectedID = themeLibraryDraft.selectedThemeID
        let fallbackID = themeLibraryDraft.activeRecords.first?.id
        selectDraft(
            themeLibraryDraft.activeRecords.contains(where: { $0.id == selectedID })
                ? selectedID
                : fallbackID
        )
    }

    private func selectDraft(_ id: UUID?) {
        stageCurrentTheme()
        guard let id,
              let record = themeLibraryDraft.activeRecords.first(where: { $0.id == id }) else {
            selectedRecordID = nil
            return
        }
        selectedRecordID = id
        theme = record.theme
        _ = themeLibraryDraft.select(id)
    }

    private func saveSelectedTheme() {
        theme.name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
        stageCurrentTheme()
        guard settingsManager.replaceThemeLibrary(themeLibraryDraft) else {
            themeImportError = "The theme library contains an invalid theme and was not saved."
            return
        }
        // The theme saved here is what All Terminals use, in place of a scheme from Terminal Themes.
        if settingsManager.terminalScheme != nil {
            settingsManager.terminalScheme = nil
            settingsManager.saveSettings()
        }
        dismiss()
    }

    private func duplicateSelectedTheme(asNewTheme: Bool) {
        stageCurrentTheme()
        guard themeLibraryDraft.activeRecords.count < TerminalThemeLibrary.maximumThemeCount,
              themeLibraryDraft.records.count < TerminalThemeLibrary.maximumRecordCount,
              let selectedRecordID,
              let source = themeLibraryDraft.activeRecords.first(where: { $0.id == selectedRecordID }) else {
            return
        }
        let copy = source.theme.reidentified(
            name: asNewTheme ? "New Theme" : "\(source.theme.name) Copy"
        )
        themeLibraryDraft.upsert(copy, origin: .custom)
        _ = themeLibraryDraft.select(copy.id)
        selectDraft(copy.id)
    }

    private func deleteSelectedTheme() {
        guard let selectedRecordID,
              !selectedThemeIsBuiltIn,
              let record = themeLibraryDraft.activeRecords.first(where: { $0.id == selectedRecordID }) else {
            return
        }
        themePendingDeletion = record
    }

    private func confirmDeleteSelectedTheme() {
        guard let record = themePendingDeletion else { return }
        themePendingDeletion = nil
        _ = themeLibraryDraft.delete(record.id)
        selectDraft(themeLibraryDraft.selectedThemeID)
    }

    private func resetSelectedTheme() {
        guard let selectedRecordID, selectedThemeIsBuiltIn else { return }
        let reset = TerminalTheme.default.reidentified(id: selectedRecordID, name: theme.name)
        themeLibraryDraft.upsert(reset, origin: .builtIn)
        selectDraft(selectedRecordID)
    }

    private func stageCurrentTheme() {
        guard let selectedRecordID,
              theme.id == selectedRecordID,
              let record = themeLibraryDraft.activeRecords.first(where: { $0.id == selectedRecordID }) else {
            return
        }
        themeLibraryDraft.upsert(theme, origin: record.origin)
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { themePendingDeletion != nil },
            set: { if !$0 { themePendingDeletion = nil } }
        )
    }

    private func originDescription(_ origin: TerminalThemeOrigin) -> String {
        switch origin {
        case .builtIn: "Built-in"
        case .custom: "Custom"
        case .appleTerminal: "Apple Terminal"
        }
    }

    #if os(macOS)
    private var appleTerminalBuiltInProfiles: [URL] {
        let directory = URL(
            fileURLWithPath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings",
            isDirectory: true
        )
        return (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?
        .filter { $0.pathExtension.lowercased() == "terminal" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        ?? []
    }

    private func importThemeFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Import Apple Terminal Profile"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "terminal") ?? .propertyList
        ]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
            }
            importTheme(at: url)
        }
    }

    private func importTheme(at url: URL) {
        do {
            stageCurrentTheme()
            let importedTheme = try TerminalThemeImportService.importTheme(
                from: url,
                fallback: theme
            )
            guard themeLibraryDraft.activeRecords.count < TerminalThemeLibrary.maximumThemeCount,
                  themeLibraryDraft.records.count < TerminalThemeLibrary.maximumRecordCount else {
                throw ThemeImportError.libraryFull
            }
            let imported = importedTheme.reidentified()
            themeLibraryDraft.upsert(imported, origin: .appleTerminal)
            _ = themeLibraryDraft.select(imported.id)
            let importedID = imported.id
            selectDraft(importedID)
        } catch {
            themeImportError = error.localizedDescription
        }
    }

    private enum ThemeImportError: LocalizedError {
        case libraryFull

        var errorDescription: String? {
            switch self {
            case .libraryFull:
                "The theme library is full. Delete a custom theme before importing another."
            }
        }
    }
    #endif
}

struct AddSSHKeyView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss
    /// The key just added, for a form that opened this sheet to choose it (B-X3).
    private let onAdded: ((StoredSSHKey) -> Void)?

    init(onAdded: ((StoredSSHKey) -> Void)? = nil) {
        self.onAdded = onAdded
    }

    @State private var name: String = ""
    @State private var privateKey: String = ""
    @State private var passphrase: String = ""
    @State private var errorMessage: String?
    @State private var inspection: SSHPrivateKeyInspection?
    @State private var showingFileImporter = false
    @FocusState private var isNameFocused: Bool
    @FocusState private var isPassphraseFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Key") {
                    TextField("Key name", text: $name, prompt: Text("Key name"))
                        .focused($isNameFocused)
                        .accessibilityIdentifier("ssh-key-name")
                    SecureField(inspection?.isPassphraseProtected == true ? "Passphrase (required for this key)" : "Passphrase (optional)",
                                text: $passphrase)
                        .focused($isPassphraseFocused)
                }

                Section {
                    // Choosing a file is the primary path; pasting is the fallback. The editor is
                    // bounded to a few lines and scrolls, so the form keeps its shape.
                    Button("Choose File…", systemImage: "doc") { chooseKeyFile() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("ssh-key-choose-file")
                    TextEditor(text: $privateKey)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 132, maxHeight: 176)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.35)))
                        .accessibilityIdentifier("ssh-key-private-key")
                    if let inspection {
                        Label {
                            Text(inspectionSummary(inspection))
                        } icon: {
                            Image(systemName: inspection.isPassphraseProtected ? "lock.fill" : "checkmark.seal")
                        }
                        .font(.footnote)
                        .foregroundStyle(inspection.isPassphraseProtected ? .orange : .secondary)
                        .accessibilityIdentifier("ssh-key-detected")
                    }
                } header: {
                    Text("Private Key")
                } footer: {
                    Text("Choose the key file or paste its contents. RSA and ED25519 private keys are supported.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            #if os(macOS)
            // A sheet on every platform (also over the server form: W4 traced the earlier crash
            // to an accessibility label, not to sheet nesting). Sized like the server form.
            .frame(minWidth: 460, idealWidth: 520, maxWidth: 560, minHeight: 440, idealHeight: 500, maxHeight: 600)
            #endif
            .navigationTitle("Add SSH Key")
            .onAppear { isNameFocused = true }
            #if !os(macOS)
            // macOS chooses through NSOpenPanel (below); the importer modifier is touch-only.
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item, .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { importKeyFile(at: url) }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            #endif
            .onChange(of: privateKey) { _, text in
                // Pasted text is classified the same way as a chosen file; nothing is stored.
                inspection = try? SSHPrivateKeyImport.inspect(text)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let added = try settingsManager.addSSHKey(
                                name: name,
                                privateKey: privateKey,
                                passphrase: passphrase.isEmpty ? nil : passphrase
                            )
                            onAdded?(added)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    // Return saves the sheet wherever there is a keyboard to press it on.
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func chooseKeyFile() {
        #if os(macOS)
        // As the theme importer does (NSOpenPanel), starting in the real ~/.ssh so keys with no
        // extension are one click away; hidden files shown because the directory itself is hidden.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = [.item, .data]
        if let home = getpwuid(getuid())?.pointee.pw_dir.map({ String(cString: $0) }) {
            let ssh = URL(fileURLWithPath: home).appendingPathComponent(".ssh", isDirectory: true)
            panel.directoryURL = FileManager.default.fileExists(atPath: ssh.path) ? ssh : URL(fileURLWithPath: home)
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importKeyFile(at: url)
        }
        #else
        showingFileImporter = true
        #endif
    }

    private func importKeyFile(at url: URL) {
        do {
            let (text, inspection) = try SSHPrivateKeyImport.read(from: url)
            privateKey = text
            self.inspection = inspection
            errorMessage = nil
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = SSHPrivateKeyImport.suggestedName(comment: inspection.comment, fileURL: url)
            }
            if inspection.isPassphraseProtected { isPassphraseFocused = true }
        } catch {
            errorMessage = error.localizedDescription
            inspection = nil
        }
    }

    private func inspectionSummary(_ inspection: SSHPrivateKeyInspection) -> String {
        var parts = ["\(inspection.keyType.displayName) key"]
        if let comment = inspection.comment, !comment.isEmpty { parts.append("comment “\(comment)”") }
        if inspection.isPassphraseProtected { parts.append("passphrase required") }
        if !inspection.keyType.isSupportedForAuthentication { parts.append("not supported for authentication") }
        return parts.joined(separator: " · ")
    }

}

struct GenerateSecureEnclaveSSHKeyView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Key Details") {
                    TextField("Key name", text: $name)
                        .focused($isNameFocused)
                    Text("Generates a hardware-bound ECDSA P-256 signing key. The private key never leaves the Secure Enclave, and each use requires user presence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Generate Key")
            .onAppear { isNameFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        do {
                            _ = try settingsManager.generateSecureEnclaveP256Key(name: name)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct RenameSSHKeyView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

    let key: StoredSSHKey
    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(key: StoredSSHKey) {
        self.key = key
        _name = State(initialValue: key.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rename") {
                    TextField("Key name", text: $name)
                        .focused($isNameFocused)
                }
            }
            .navigationTitle("Rename SSH Key")
            .onAppear { isNameFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settingsManager.renameSSHKey(key.id, name: name)
                        dismiss()
                    }
                    // A key with no name cannot be told apart in the list or chosen in a form.
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()

#Preview {
    TerminalSettingsView()
        .environment(SettingsManager())
        .environment(SessionManager(loadImmediately: false))
}

/// The host keys this app trusts, and a way to forget one (help audit: there was none). One row per
/// host and port, with each active key's type and fingerprint.
private struct TrustedHostKeysSection: View {
    @State private var keys: [PinnedSSHHostKey] = []
    @State private var loadError: String?
    @State private var forgetting: Endpoint?

    private struct Endpoint: Identifiable, Hashable {
        var host: String
        var port: Int
        var id: String { "\(host):\(port)" }
    }

    private var endpoints: [(Endpoint, [PinnedSSHHostKey])] {
        let active = keys.filter { $0.state == .active }
        let grouped = Dictionary(grouping: active) { Endpoint(host: $0.host, port: $0.port) }
        return grouped.sorted { $0.key.id.localizedStandardCompare($1.key.id) == .orderedAscending }
    }

    var body: some View {
        Section {
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if endpoints.isEmpty {
                Text("No host keys are trusted yet. A key is trusted the first time you accept it when connecting.")
                    .foregroundStyle(.secondary)
            }
            ForEach(endpoints, id: \.0) { endpoint, hostKeys in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(endpoint.port == 22 ? endpoint.host : "\(endpoint.host):\(endpoint.port)")
                            .fontWeight(.medium)
                        ForEach(hostKeys) { key in
                            Text("\(key.algorithm)  \(key.sha256Fingerprint)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("Last seen \(key.lastSeenAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("Forget…", role: .destructive) { forgetting = endpoint }
                        .accessibilityLabel("Forget the host key for \(endpoint.host)")
                }
            }
        } header: {
            Text("Trusted Host Keys")
        } footer: {
            Text("Trusted keys sync to your other devices through iCloud Keychain. Forgetting one forgets it everywhere; the next connection asks you to check the key again.")
        }
        .task { reload() }
        .confirmationDialog("Forget this host key?", isPresented: Binding(get: { forgetting != nil },
                                                                          set: { if !$0 { forgetting = nil } }),
                            titleVisibility: .visible, presenting: forgetting) { endpoint in
            Button("Forget", role: .destructive) {
                do {
                    try KeychainManager.forgetHostKeys(host: endpoint.host, port: endpoint.port)
                } catch {
                    loadError = "The key could not be forgotten. \(error.localizedDescription)"
                }
                forgetting = nil
                reload()
            }
            Button("Cancel", role: .cancel) { forgetting = nil }
        } message: { endpoint in
            Text("\(endpoint.host) will have to show its key again, on every device, before it is trusted.")
        }
    }

    private func reload() {
        do {
            keys = try KeychainManager.allPinnedHostKeys()
            loadError = nil
        } catch {
            loadError = "Trusted host keys could not be read. \(error.localizedDescription)"
        }
    }
}
