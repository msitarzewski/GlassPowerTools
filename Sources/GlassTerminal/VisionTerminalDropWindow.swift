//
//  VisionTerminalDropWindow.swift
//  Glass Power Tools — GlassTerminal
//
//  A terminal window made by dropping a terminal dragged out of the library (D72, 2026-10-13: "Be
//  sure visionOS is well represented!"): it stands where it was let go, in the room, and becomes that
//  machine's terminal. The drag carries an activity naming the service (`GlassServiceDrag`); this
//  window reserves a workgroup for the server, asks to connect the way the library's Connect does —
//  sign-in and host trust as usual — and shows the workgroup once the session is in it. A failed or
//  declined connection says so and closes; a window with no activity at all is the old "not found".
//

#if os(visionOS)
import GlassShell
import SwiftUI

struct VisionTerminalDropWindow: View {
    @Environment(GlassTerminalRuntime.self) private var runtime
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss

    @State private var reserved: UUID?
    @State private var serverName: String?
    @State private var failure: String?
    /// A moment for the drop's activity to arrive before the window says it has nothing to show.
    @State private var waited = false

    var body: some View {
        Group {
            if let reserved, sessionManager.workgroup(for: reserved) != nil {
                VisionTerminalWorkgroupView(workgroupID: reserved)
                    .modifier(TerminalWorkgroupWindowPresence(workgroupID: reserved))
            } else if let failure {
                ContentUnavailableView {
                    Label("Could Not Connect", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Close") { dismiss() }
                }
            } else if reserved != nil || !waited {
                ProgressView(serverName.map { "Connecting to \($0)…" } ?? "Connecting…")
                    .controlSize(.large)
            } else {
                ContentUnavailableView(
                    "Terminal Workgroup Not Found",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text("Open a terminal from Connections to begin.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onContinueUserActivity(GlassServiceDrag.terminalActivity) { activity in
            guard reserved == nil, let serverID = GlassServiceDrag.endpoint(from: activity) else { return }
            serverName = runtime.savedServerName(id: serverID)
            let workgroupID = runtime.reserveWindow(forServer: serverID)
            reserved = workgroupID
            runtime.requestConnect(serverID: serverID, report: { outcome in
                switch outcome {
                case .connected:
                    break
                case .failed(let message):
                    runtime.releaseReservation(workgroupID)
                    self.reserved = nil
                    failure = message
                case .dismissed:
                    runtime.releaseReservation(workgroupID)
                    dismiss()
                }
            })
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            waited = true
        }
    }
}
#endif
