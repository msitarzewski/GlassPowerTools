//
//  GlassCommandPalette.swift
//  Glass Power Tools — GlassLayers
//
//  One macOS command palette for the whole product.
//
//  `GlassTerminal` and `GlassDatabase` each carried their own copy of this file's contents —
//  byte-for-byte identical, 286 lines, including their own `MacCommandCenterEntry` type and their
//  own `macCommandCenterEntries` focused-value key with the same name. Same names, different
//  types: a database workspace's entries could never reach the terminal's palette and vice versa,
//  so a merged product had two command palettes that could not see each other's commands.
//
//  Extracted here because both modules already depend on `GlassLayers` and neither may depend on
//  the other. Capabilities contribute entries through the focused value, as they contribute
//  settings pages and service tools elsewhere.
//
//  Note on D16: sharing across a module boundary broke the Release link once already, for an
//  `if #available` inside a `@ToolbarContentBuilder`. Nothing here is a result builder — it is
//  AppKit plus a plain `FocusedValues` property — and a Release build was run to confirm it.
//

#if os(macOS)
import AppKit
import SwiftUI

public struct MacCommandCenterEntry: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public var shortcut: String = ""
    public var isEnabled = true
    public var completion: String? = nil
    public let action: () -> Void

    public init(id: String, title: String, detail: String, shortcut: String = "",
                isEnabled: Bool = true, completion: String? = nil,
                action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.detail = detail
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.completion = completion
        self.action = action
    }

    public static func matches(_ query: String, title: String, detail: String) -> Bool {
        let haystack = (title + " " + detail).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).allSatisfy { token in
                var remaining = haystack[...]
                for character in token {
                    guard let index = remaining.firstIndex(of: character) else { return false }
                    remaining = remaining[remaining.index(after: index)...]
                }
                return true
            }
    }
}

private struct MacCommandCenterEntriesKey: FocusedValueKey {
    typealias Value = [MacCommandCenterEntry]
}

public extension FocusedValues {
    var macCommandCenterEntries: [MacCommandCenterEntry]? {
        get { self[MacCommandCenterEntriesKey.self] }
        set { self[MacCommandCenterEntriesKey.self] = newValue }
    }
}

/// A native sheet over the originating window. Reuses menu targets and restores
/// the responder before invoking them; no second SQL/terminal execution path.
@MainActor
final class MacCommandCenter: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    static let shared = MacCommandCenter()
    private var panel: NSPanel?
    private let search = NSSearchField()
    private let table = CommandCenterTableView()
    private let footer = NSTextField(labelWithString: "")
    private var entries: [MacCommandCenterEntry] = []
    private var filtered: [MacCommandCenterEntry] = []
    private weak var sourceWindow: NSWindow?
    private weak var sourceResponder: NSResponder?
    private var recentIDs: [String] = []
    private var destinationLoader: ((String) async throws -> [MacCommandCenterEntry])?
    private var destinationTask: Task<Void, Never>?
    private var dynamicEntries: [MacCommandCenterEntry] = []
    private var isDismissing = false

    func present(additionalEntries: [MacCommandCenterEntry] = [],
                 destinations: ((String) async throws -> [MacCommandCenterEntry])? = nil) {
        guard panel?.isVisible != true, let window = NSApp.keyWindow,
              window.attachedSheet == nil, window.sheetParent == nil else { NSSound.beep(); return }
        sourceWindow = window
        sourceResponder = window.firstResponder
        destinationLoader = destinations
        dynamicEntries = []
        entries = additionalEntries + menuEntries(NSApp.mainMenu, path: [], depth: 0)
        if panel == nil { configurePanel() }
        search.stringValue = ""
        filterEntries()
        guard let panel else { return }
        let width = min(660, max(360, window.frame.width - 48))
        panel.setFrame(NSRect(x: window.frame.midX - width / 2,
                              y: window.frame.maxY - 90 - 420,
                              width: width, height: 420), display: false)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
        loadDestinations()
    }

    func menuEntries(_ menu: NSMenu?, path: [String], depth: Int) -> [MacCommandCenterEntry] {
        guard let menu, depth < 6 else { return [] }
        menu.update()
        return menu.items.enumerated().flatMap { index, item -> [MacCommandCenterEntry] in
            guard !item.isSeparatorItem, !item.isHidden, !item.title.isEmpty,
                  !item.title.hasPrefix("Command Palette"), item.title != "Services" else { return [] }
            let route = path + [item.title]
            if let submenu = item.submenu { return menuEntries(submenu, path: route, depth: depth + 1) }
            // SwiftUI clears the selector of some disabled commands.
            guard item.action != nil || !item.isEnabled else { return [] }
            let enabled = item.isEnabled
            let modifiers = item.keyEquivalentModifierMask
            let shortcut = (modifiers.contains(.control) ? "⌃" : "")
                + (modifiers.contains(.option) ? "⌥" : "")
                + (modifiers.contains(.shift) ? "⇧" : "")
                + (modifiers.contains(.command) ? "⌘" : "")
                + item.keyEquivalent.uppercased().replacingOccurrences(of: "\r", with: "↩")
            return [MacCommandCenterEntry(
                id: "menu." + route.joined(separator: "/") + ".\(index)",
                title: (path.last.map { $0 + ": " } ?? "") + item.title,
                detail: path.joined(separator: " › ") + (enabled ? "" : " — Unavailable in this window"),
                shortcut: item.keyEquivalent.isEmpty ? "" : shortcut,
                isEnabled: enabled
            ) { [weak item] in
                guard let item else { return }
                item.menu?.update()
                guard item.isEnabled, let action = item.action else { NSSound.beep(); return }
                NSApp.sendAction(action, to: item.target, from: item)
            }]
        }
    }

    private func configurePanel() {
        let panel = CommandPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Command Palette"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.masksToBounds = true
        panel.contentView = material
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        search.placeholderString = "Search commands and destinations"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Search commands and destinations")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 34
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.backgroundColor = .clear
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(performSelected)
        table.onAccept = { [weak self] in self?.performSelected() }
        table.onCancel = { [weak self] in self?.dismiss(action: nil) }
        table.setAccessibilityLabel("Matching commands")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footer.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [search, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = panel.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            search.heightAnchor.constraint(equalToConstant: 28)
        ])
        self.panel = panel
    }

    func controlTextDidChange(_ obj: Notification) {
        dynamicEntries = []
        filterEntries()
        loadDestinations()
    }

    private func loadDestinations() {
        destinationTask?.cancel()
        guard let destinationLoader else { return }
        let query = search.stringValue
        destinationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                let loaded = try await destinationLoader(query)
                try Task.checkCancellation()
                guard let self, self.panel?.isVisible == true, self.search.stringValue == query else { return }
                self.dynamicEntries = loaded
                self.filterEntries()
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.footer.stringValue = "Could not load connected database names. Existing commands are still available."
            }
        }
    }

    private func filterEntries() {
        let query = search.stringValue.lowercased()
        let recentIDs = self.recentIDs
        filtered = (entries + dynamicEntries).filter {
            if query.hasPrefix("connect:") {
                return $0.id.hasPrefix("connection.connect.") &&
                    MacCommandCenterEntry.matches(String(query.dropFirst(8)), title: $0.title, detail: $0.detail)
            }
            return MacCommandCenterEntry.matches(query, title: $0.title, detail: $0.detail)
        }.enumerated().sorted { lhs, rhs in
            func score(_ entry: MacCommandCenterEntry) -> Int {
                (entry.isEnabled ? 1000 : 0)
                + (entry.completion != nil && !query.isEmpty && entry.title.lowercased().hasPrefix(query) ? 200 : 0)
                + (query.isEmpty ? 0 : entry.title.lowercased().contains(query) ? 100 : 0)
                + (recentIDs.firstIndex(of: entry.id).map { 50 - $0 } ?? 0)
            }
            let a = score(lhs.element), b = score(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a > b
        }.map(\.element)
        table.reloadData()
        if let index = filtered.firstIndex(where: \.isEnabled) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        } else { table.deselectAll(nil) }
        footer.stringValue = filtered.isEmpty ? "No matching commands" : "\(filtered.count) results · ↑↓ Navigate · Return Run · Escape Cancel"
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        title.textColor = entry.isEnabled ? .labelColor : .secondaryLabelColor
        let detail = NSTextField(labelWithString: entry.shortcut)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        detail.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.toolTip = entry.detail
        stack.setAccessibilityLabel(entry.title + ", " + entry.detail)
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        return stack
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch NSStringFromSelector(commandSelector) {
        case "insertTab:":
            guard filtered.indices.contains(table.selectedRow),
                  let completion = filtered[table.selectedRow].completion else { return false }
            search.stringValue = completion
            dynamicEntries = []
            filterEntries()
            loadDestinations()
            return true
        case "moveDown:", "moveUp:":
            guard !filtered.isEmpty else { return true }
            let delta = NSStringFromSelector(commandSelector) == "moveDown:" ? 1 : -1
            let row = min(filtered.count - 1, max(0, table.selectedRow + delta))
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        case "insertNewline:": performSelected(); return true
        case "cancelOperation:": dismiss(action: nil); return true
        default: return false
        }
    }

    @objc private func performSelected() {
        guard filtered.indices.contains(table.selectedRow),
              filtered[table.selectedRow].isEnabled else { NSSound.beep(); return }
        let entry = filtered[table.selectedRow]
        recentIDs.removeAll { $0 == entry.id }
        recentIDs.insert(entry.id, at: 0)
        recentIDs = Array(recentIDs.prefix(20))
        dismiss(action: entry.action)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(action: nil); return false }
    func windowDidResignKey(_ notification: Notification) {
        if panel?.isVisible == true { dismiss(action: nil, restoreFocus: false) }
    }

    private func dismiss(action: (() -> Void)?, restoreFocus: Bool = true) {
        guard !isDismissing, let panel, panel.isVisible, let window = sourceWindow else { return }
        isDismissing = true
        defer { isDismissing = false }
        let responder = sourceResponder
        destinationTask?.cancel()
        destinationLoader = nil
        dynamicEntries = []
        window.removeChildWindow(panel)
        panel.orderOut(nil)
        entries = []
        filtered = []
        DispatchQueue.main.async {
            guard restoreFocus, window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
            if let responder { window.makeFirstResponder(responder) }
            // Allow SwiftUI focused commands to update after returning the key window.
            DispatchQueue.main.async { action?() }
        }
    }
}

@MainActor
private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CommandCenterTableView: NSTableView {
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onAccept?()
        case 53: onCancel?()
        default: super.keyDown(with: event)
        }
    }
}


/// How a capability opens the one command palette. The centre itself stays internal — consumers
/// present it and contribute entries; they have no business with its table view or its responder
/// handling.
public enum GlassCommandPalette {
    /// Opens the palette over the key window. `additionalEntries` are the caller's own commands,
    /// shown above the menu bar's; `destinations` supplies matches for a typed query, so a
    /// capability can offer its databases, tables or sessions without this module knowing what
    /// those are.
    @MainActor
    public static func present(
        additionalEntries: [MacCommandCenterEntry] = [],
        destinations: ((String) async throws -> [MacCommandCenterEntry])? = nil
    ) {
        MacCommandCenter.shared.present(additionalEntries: additionalEntries, destinations: destinations)
    }
}

#endif
