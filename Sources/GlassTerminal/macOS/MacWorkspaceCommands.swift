#if os(macOS)
#if os(macOS)
import AppKit
import SwiftUI
import GlassLayers

@MainActor
struct MacWorkspaceFocusedActions {
    let workspaceID: UUID
    let canAddPane: Bool
    let hasFocusedPane: Bool
    let secureKeyboardEntryEnabled: Bool
    let addLocalPane: (MacWorkspaceSplitAxis) -> Void
    let requestSSHPane: (MacWorkspaceSplitAxis) -> Void
    let closeFocusedPane: () -> Void
    let focusNextPane: () -> Void
    let findInFocusedPane: () -> Void
    let toggleSecureKeyboardEntry: () -> Void
}

@MainActor
struct MacNewWorkspaceTabAction {
    let isEnabled: Bool
    private let action: () -> Void

    init(isEnabled: Bool, _ action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    func callAsFunction() {
        guard isEnabled else { return }
        action()
    }
}

@MainActor
struct MacCloseWorkspaceTabAction {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func callAsFunction() {
        action()
    }
}

private struct MacWorkspaceFocusedActionsKey: FocusedValueKey {
    typealias Value = MacWorkspaceFocusedActions
}

private struct MacNewWorkspaceTabActionKey: FocusedValueKey {
    typealias Value = MacNewWorkspaceTabAction
}

private struct MacCloseWorkspaceTabActionKey: FocusedValueKey {
    typealias Value = MacCloseWorkspaceTabAction
}

extension FocusedValues {
    var macCloseWorkspaceTabAction: MacCloseWorkspaceTabAction? {
        get { self[MacCloseWorkspaceTabActionKey.self] }
        set { self[MacCloseWorkspaceTabActionKey.self] = newValue }
    }

    var macWorkspaceActions: MacWorkspaceFocusedActions? {
        get { self[MacWorkspaceFocusedActionsKey.self] }
        set { self[MacWorkspaceFocusedActionsKey.self] = newValue }
    }

    var macNewWorkspaceTabAction: MacNewWorkspaceTabAction? {
        get { self[MacNewWorkspaceTabActionKey.self] }
        set { self[MacNewWorkspaceTabActionKey.self] = newValue }
    }
}

struct MacWorkspaceCommands: Commands {
    let sessionManager: SessionManager
    @FocusedValue(\.macCommandCenterEntries) private var commandCenterEntries
    @FocusedValue(\.terminalFontActions) private var fontActions
    @FocusedValue(\.macWorkspaceActions) private var actions
    @FocusedValue(\.macNewWorkspaceTabAction) private var newWorkspaceTabAction
    @FocusedValue(\.macCloseWorkspaceTabAction) private var closeWorkspaceTabAction
    @Environment(\.openWindow) private var openWindow

    private func presentCommandPalette() {
        let connections = sessionManager.serverManager.servers.map { server in
            MacCommandCenterEntry(id: "connection.connect.\(server.id)", title: "connect: \(server.name)",
                                  detail: "Open an SSH terminal window") {
                sessionManager.paletteConnectionRequest = server.id
                openWindow(id: "main")
            }
        }
        GlassCommandPalette.present(additionalEntries:
            connections + (commandCenterEntries ?? []).filter { !$0.id.hasPrefix("connection.connect.") })
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Terminal Grid") {
                commandCenterEntries?.first { $0.id == "workspace.grid" }?.action()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(commandCenterEntries?.contains { $0.id == "workspace.grid" } != true)
            Button("Terminal Carousel") {
                commandCenterEntries?.first { $0.id == "workspace.carousel" }?.action()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(commandCenterEntries?.contains { $0.id == "workspace.carousel" } != true)
            Divider()
            ForEach(1...9, id: \.self) { number in
                let entry = commandCenterEntries?.first { $0.id == "workspace.tab.\(number)" }
                Button(entry.map { "Tab \(number): \($0.title)" } ?? "Tab \(number)") {
                    entry?.action()
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                .disabled(entry == nil)
            }
        }
        CommandGroup(after: .appInfo) {
            Button("Command Palette…") {
                presentCommandPalette()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Command Palette (Alternate)…") {
                presentCommandPalette()
            }
            .keyboardShortcut("k", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Terminal Window") {
                openWindow(id: "workspace", value: MacWorkspaceLaunchRequest())
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Workspace Tab") {
                if let newWorkspaceTabAction {
                    newWorkspaceTabAction()
                } else {
                    openWindow(
                        id: "workspace",
                        value: MacWorkspaceLaunchRequest(startsEmpty: true)
                    )
                }
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(newWorkspaceTabAction?.isEnabled == false)

            Button("Connect Saved Host…") {
                actions?.requestSSHPane(.horizontal)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(actions?.canAddPane != true)
        }

        // Replace the native Close command instead of registering a second
        // Cmd-W shortcut that could still close the whole workspace window.
        CommandGroup(replacing: .saveItem) {
            Button(closeWorkspaceTabAction == nil ? "Close Window" : "Close Tab") {
                guard let window = NSApp.keyWindow,
                      window.attachedSheet == nil,
                      window.sheetParent == nil else { return }
                if let closeWorkspaceTabAction {
                    closeWorkspaceTabAction()
                } else {
                    window.performClose(nil)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandMenu("Terminal") {
            Button("Increase Font Size") { fontActions?.increase() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(fontActions == nil)
            Button("Increase Font Size") { fontActions?.increase() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(fontActions == nil)
                .hidden()
            Button("Decrease Font Size") { fontActions?.decrease() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(fontActions == nil)
            Button("Reset Font Size") { fontActions?.reset() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(fontActions == nil)

            Divider()

            Button("Find in Pane…") {
                actions?.findInFocusedPane()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions?.hasFocusedPane != true)

            Divider()

            Button("Split Right") {
                actions?.addLocalPane(.horizontal)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(actions?.canAddPane != true)

            Button("Split Down") {
                actions?.addLocalPane(.vertical)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(actions?.canAddPane != true)

            Button("Connect Saved Host in Split…") {
                actions?.requestSSHPane(.horizontal)
            }
            .disabled(actions?.canAddPane != true)

            Divider()

            Button("Focus Next Pane") {
                actions?.focusNextPane()
            }
            .keyboardShortcut("]", modifiers: [.command, .option])
            .disabled(actions?.hasFocusedPane != true)

            Button("Close Pane") {
                actions?.closeFocusedPane()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(actions?.hasFocusedPane != true)

            Divider()

            Button {
                actions?.toggleSecureKeyboardEntry()
            } label: {
                if actions?.secureKeyboardEntryEnabled == true {
                    Label("Secure Keyboard Entry", systemImage: "checkmark")
                } else {
                    Text("Secure Keyboard Entry")
                }
            }
            .disabled(actions?.hasFocusedPane != true)
        }
    }
}
#endif
#if os(macOS)
/// Snapshot of an existing action; opening the palette never executes commands.
// The command palette lives in GlassLayers: both capabilities contribute entries to one
// surface. This file used to carry a byte-for-byte copy of it.

#endif

#endif
