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
    /// What the focused tab is connected to, for naming the ⇧⌘T item after the machine — "New Tab
    /// on oscar" rather than a description of the mechanism. Nil when the focused tab has nothing to
    /// repeat: an empty tab has no connection to carry over, and the item says so by being absent.
    let currentConnectionName: String?
    private let action: () -> Void
    private let repeatAction: () -> Void

    init(isEnabled: Bool, currentConnectionName: String? = nil,
         _ action: @escaping () -> Void,
         repeatingCurrentConnection repeatAction: @escaping () -> Void = {}) {
        self.isEnabled = isEnabled
        self.currentConnectionName = currentConnectionName
        self.action = action
        self.repeatAction = repeatAction
    }

    var canRepeatCurrentConnection: Bool { isEnabled && currentConnectionName != nil }

    /// "New Tab on oscar" — the title carries the machine, so the menu says what will happen.
    var repeatTitle: String {
        currentConnectionName.map { "New Tab on \($0)" } ?? "New Tab with Same Connection"
    }

    func callAsFunction() {
        guard isEnabled else { return }
        action()
    }

    /// A second tab on whatever the focused one is running, with no chooser in between.
    func repeatingCurrentConnection() {
        guard canRepeatCurrentConnection else { return }
        repeatAction()
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
        // The terminal's File items, **added after** the shell's New group and never replacing it.
        //
        // Two scenes replacing the same placement is not a merge — SwiftUI keeps one of them, and
        // on 2026-09-16 the one it kept was the database's: `New Terminal Window`, `New Terminal
        // Tab` and `Connect Saved Host…` were absent from the shipped menu bar (read back out of
        // the running app through the accessibility API, not inferred). ⌘T did nothing, which is
        // exactly what the user reported. `GlassShellFileCommands` is the single owner of the
        // placement now, and every capability appends to it.
        CommandGroup(after: .newItem) {
            // No ⌘N here: ⌘N is the shell's one contextual New, and this window publishes
            // `\.glassNewItem` so that when a terminal workspace is focused ⌘N *is* this item
            // (`MacWorkspaceView.swift`). Keeping it in the menu unbound leaves it discoverable
            // from any window, including the library.
            Button("New Terminal Window") {
                openWindow(id: "workspace", value: MacWorkspaceLaunchRequest())
            }

            Button("New Terminal Tab") {
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

            // ⇧⌘T: another tab on the machine this one is already on, with no chooser. The whole
            // point is that it asks nothing — the pane intent is copied, so the new tab connects
            // through the same saved server, credentials and trust the focused tab used.
            Button(newWorkspaceTabAction?.repeatTitle ?? "New Tab with Same Connection") {
                newWorkspaceTabAction?.repeatingCurrentConnection()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(newWorkspaceTabAction?.canRepeatCurrentConnection != true)

            Button("Connect Saved Host…") {
                actions?.requestSSHPane(.horizontal)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(actions?.canAddPane != true)
        }

        // **Close Tab, in a placement that exists.**
        //
        // This was `CommandGroup(replacing: .saveItem)`, which produced nothing at all: `.saveItem`
        // is the document group — Save, Duplicate, Rename, Revert — and an app with no documents
        // has none, so there was nothing to replace and the item never reached the menu bar. Read
        // back from the running app on 2026-09-16: no Close Tab anywhere in it, and ⌘W was
        // AppKit's own Close, which shuts the whole workspace window with every tab in it.
        //
        // `after: .newItem` is a region that does materialise (the database's items land there).
        // Two items can carry ⌘W because AppKit skips a disabled item when matching a key
        // equivalent: with a terminal workspace focused this one is enabled and closes the tab,
        // and with anything else focused it is disabled and the standard Close below it answers.
        // That is why the "Close Window" fallback is gone — it existed to stand in for the very
        // item it was shadowing.
        CommandGroup(after: .newItem) {
            Divider()
            Button("Close Tab") {
                guard let window = NSApp.keyWindow,
                      window.attachedSheet == nil,
                      window.sheetParent == nil else { return }
                closeWorkspaceTabAction?()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(closeWorkspaceTabAction == nil)
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
