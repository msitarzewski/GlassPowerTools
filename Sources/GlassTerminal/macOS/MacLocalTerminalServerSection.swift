//
//  MacLocalTerminalServerSection.swift
//  Glass Power Tools — GlassTerminal
//
//  Settings ▸ Terminal: the background process local terminals run in (D66, `MacTmuxHost`), and a
//  way to end it (the owner, 2026-10-12: "give the user a way to terminate it in the settings >
//  terminal tab"). It stops by itself when the last terminal ends; ending it here ends them all.
//

#if os(macOS)
import SwiftUI

struct MacLocalTerminalServerSection: View {
    /// Terminals tmux runs on this Mac; nil until asked, 0 when no server runs.
    @State private var sessions: Int?
    @State private var confirming = false
    @State private var ending = false

    var body: some View {
        Section("Local Terminals in the Background") {
            LabeledContent("Status", value: status)
                .accessibilityIdentifier("settings.local-terminals-status")
            Button("End All Local Terminals…", role: .destructive) { confirming = true }
                .disabled((sessions ?? 0) == 0 || ending)
                .accessibilityIdentifier("settings.end-local-terminals")
            Text("Local terminals kept in tmux run in a background Glass Power Tools process, so quitting or updating the app, or force quitting another app, leaves them running. It stops by itself when the last one ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
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
