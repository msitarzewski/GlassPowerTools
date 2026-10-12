//
//  MacLocalTerminalServerSection.swift
//  Glass Power Tools — GlassTerminal
//
//  Settings ▸ Terminal ▸ tmux: whether local terminals run in tmux (moved from Connections on
//  2026-10-12, so everything about local tmux is in one place), the background process they run
//  in (D66, `MacTmuxHost`), and a way to end it (the owner, 2026-10-12: "give the user a way to
//  terminate it in the settings > terminal tab"). It stops by itself when the last terminal ends;
//  ending it here ends them all. New Basic Terminal Tab (⌃⌘T) opens one outside tmux either way.
//

#if os(macOS)
import SwiftUI

struct MacLocalTerminalServerSection: View {
    @Bindable var settings: SettingsManager
    @State private var tmuxPath: String?
    /// Terminals tmux runs on this Mac; nil until asked, 0 when no server runs.
    @State private var sessions: Int?
    @State private var confirming = false
    @State private var ending = false

    var body: some View {
        Section("tmux") {
            Toggle("Keep local terminals running with tmux", isOn: $settings.localTmux)
                .disabled(tmuxPath == nil && !settings.localTmux)
                .onChange(of: settings.localTmux) { _, _ in settings.saveSettings() }
                .accessibilityIdentifier("settings.local-tmux")
            Text(tmuxPath == nil
                 ? "tmux isn't installed on this Mac. Install it with Homebrew (brew install tmux), then come back here."
                 : "Quitting or updating the app leaves local terminals running, and each tab picks up where it was when the app opens again. Closing a tab leaves its terminal running too: Active lists it under This Mac, to open again or end. New Basic Terminal Tab (⌃⌘T) opens one outside tmux.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if tmuxPath != nil {
                LabeledContent("Running in the background", value: status)
                    .accessibilityIdentifier("settings.local-terminals-status")
                Button("End All Local Terminals…", role: .destructive) { confirming = true }
                    .disabled((sessions ?? 0) == 0 || ending)
                    .accessibilityIdentifier("settings.end-local-terminals")
                Text("Local terminals in tmux run in a background Glass Power Tools process, so quitting or updating the app, or force quitting another app, leaves them running. It stops by itself when the last one ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Each saved host has its own tmux setting, in its editor. A host that keeps its terminals in tmux also offers Basic Terminal, for a shell outside it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            tmuxPath = MacLocalTmux.executablePath()
            // Kept current while Settings shows it: terminals end, and new ones start, elsewhere.
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .alert("End all local terminals?", isPresented: $confirming) {
            Button("End All", role: .destructive) { Task { await endAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This ends tmux on this Mac and \(terminals(sessions ?? 0)) in it, with whatever they are running. Their tabs close.")
        }
    }

    private var status: String {
        guard let sessions else { return "Checking…" }
        return sessions == 0 ? "Not running" : "Running, \(terminals(sessions))"
    }

    private func terminals(_ count: Int) -> String {
        count == 1 ? "1 terminal" : "\(count) terminals"
    }

    private func refresh() async {
        let server = MacLocalTmux.server
        guard let tmux = server.executablePath() else {
            sessions = 0
            return
        }
        let output = await Task.detached { server.listSessions(tmux) }.value
        sessions = MacLocalTmux.sessions(from: output).count
    }

    private func endAll() async {
        ending = true
        let server = MacLocalTmux.server
        if let tmux = server.executablePath() {
            await Task.detached { server.endServer(tmux) }.value
        }
        ending = false
        await refresh()
    }
}
#endif
