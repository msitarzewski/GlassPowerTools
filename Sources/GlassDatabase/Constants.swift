//
//  Constants.swift
//  glassdb
//
//  Typed constants for UserDefaults keys.
//  Keychain service names are now derived from the shared GlasSecretStore configuration.
//

import Foundation
import SwiftUI
import GlassConnectionUI
import GlassDBKit
import GlassLayers
import GlasSecretStore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The defaults keys glassdb wrote, carried over verbatim. They are namespaced `glassdb.`
/// rather than renamed because these strings are the only handle a later import of an existing
/// glassdb installation would have: `UserDefaults.standard` is per bundle identifier, so a new
/// bundle starts with none of this data and only the old names can find it.
enum UserDefaultsKeys {
    static let connections = "glassdb.connections"
    static let savedQueries = "glassdb.savedQueries"
    static let queryHistory = "glassdb.queryHistory"
    static let sshKeys = "glassdb.sshKeys"
    static let mutationAudit = "glassdb.mutationAudit.v1"

    // Settings
    static let maxQueryHistoryItems = "glassdb.maxQueryHistoryItems"
    static let resultRowLimit = "glassdb.resultRowLimit"
    static let windowOpacity = "glassdb.windowOpacity"
    static let blurBackground = "glassdb.blurBackground"
    static let showSidebarByDefault = "glassdb.showSidebarByDefault"
    static let editorFontSize = "glassdb.editorFontSize"
    static let dataGridFontSize = "glassdb.dataGridFontSize"
    static let showLineNumbers = "glassdb.showLineNumbers"
    static let autoFormatJSONInRecordEditor = "glassdb.autoFormatJSONInRecordEditor"
    static let redactQueryHistoryLiterals = "glassdb.redactQueryHistoryLiterals"
    static let queryFailureNotificationPreference = "glassdb.queryFailureNotificationPreference"
}

enum KeychainServiceNames {
    private static let config = KeychainManager.config
    static var passwords: String { config.passwordsService }
    static var sshPasswords: String { config.sshPasswordsService }
    static var sshKeysPrivate: String { config.sshKeysPrivateService }
    static var sshKeysPassphrase: String { config.sshKeysPassphraseService }
    static var sealedP256: String { config.sealedP256Service }
    static var sealedP256Tag: String { config.sealedP256TagService }
}

// MARK: - Shared platform adapters

/// Connection library column metrics, mirrored from glas.sh's
/// `ConnectionLibraryMacColumnLayout` (`ConnectionManagerView.swift:16-23`) so
/// both Glass-family Connections windows open at the same proportions. These
/// are deliberately separate from `DatabaseSidebarLayout`, which measures the
/// database workspace's schema sidebar, not this window.
enum ConnectionLibraryColumnLayout {
    static let navigationMinimum: CGFloat = GlassLibraryColumnLayout.navigationMinimum
    static let navigationIdeal: CGFloat = GlassLibraryColumnLayout.navigationIdeal
    static let navigationMaximum: CGFloat = GlassLibraryColumnLayout.navigationMaximum
    static let resultsMinimum: CGFloat = GlassLibraryColumnLayout.resultsMinimum
    static let resultsIdeal: CGFloat = GlassLibraryColumnLayout.resultsIdeal
    static let resultsMaximum: CGFloat = GlassLibraryColumnLayout.resultsMaximum
    /// AppKit persists the user's divider positions under this name, so a
    /// resize survives relaunch. Namespaced to glassdb; glas.sh keeps its own.
    static let autosaveName = "app.glassdb.connection-library.columns"
}

enum DatabaseSidebarLayout {
    static let minimumWidth: CGFloat = 300
    static let idealWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 440
}

/// Canonical independent levels for database-canvas paint and passthrough
/// blur. Foreground content never inherits either value.
struct DatabaseGlassAppearance: Equatable, Sendable {
    let opacity: Double
    let blur: Double

    init(opacity: Double, blur: Double) {
        self.opacity = Self.unitValue(opacity)
        self.blur = Self.unitValue(blur)
    }

    var paintsCanvas: Bool { opacity > 0 }
    var compositesBlur: Bool { blur > 0 }
    var isFullyTransparent: Bool { !paintsCanvas && !compositesBlur }

    func surfaceAlpha(strength: Double = 0.06) -> Double {
        opacity * Self.unitValue(strength)
    }

    /// Pinned content must occlude scrolling text while preserving the exact
    /// transparent and opaque endpoints selected by the user.
    var pinnedSurfaceAlpha: Double {
        sqrt(opacity)
    }

    /// visionOS composites its database canvas with a SwiftUI material rather
    /// than AppKit's behind-window effect. Strengthen that local material under
    /// pinned grid chrome so scrolling values cannot visually merge with it.
    var pinnedBlurAlpha: Double {
        sqrt(blur)
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

enum DatabaseCanvasPalette {
    @MainActor
    static var background: Color {
        #if canImport(AppKit)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

enum PlatformClipboard {
    static func copy(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

extension View {
    @ViewBuilder
    func databaseSidebarColumnWidth() -> some View {
        #if os(macOS)
        navigationSplitViewColumnWidth(
            min: DatabaseSidebarLayout.minimumWidth,
            ideal: DatabaseSidebarLayout.idealWidth,
            max: DatabaseSidebarLayout.maximumWidth
        )
        #else
        self
        #endif
    }

    /// Attaches AppKit's split-view autosave so the user's own column widths
    /// replace the defaults after the first resize. Mirrors glas.sh's
    /// `MacConnectionLibrarySplitViewAutosave`.
    @ViewBuilder
    func connectionLibraryColumnAutosave() -> some View {
        #if os(macOS)
        glassLibraryColumnAutosave(ConnectionLibraryColumnLayout.autosaveName)
        #else
        self
        #endif
    }

    @ViewBuilder
    func connectionLibraryNavigationColumnWidth() -> some View {
        #if os(macOS)
        navigationSplitViewColumnWidth(
            min: ConnectionLibraryColumnLayout.navigationMinimum,
            ideal: ConnectionLibraryColumnLayout.navigationIdeal,
            max: ConnectionLibraryColumnLayout.navigationMaximum
        )
        #else
        self
        #endif
    }

    @ViewBuilder
    func connectionLibraryResultsColumnWidth() -> some View {
        #if os(macOS)
        navigationSplitViewColumnWidth(
            min: ConnectionLibraryColumnLayout.resultsMinimum,
            ideal: ConnectionLibraryColumnLayout.resultsIdeal,
            max: ConnectionLibraryColumnLayout.resultsMaximum
        )
        #else
        self
        #endif
    }

    @ViewBuilder
    func databaseLookScrollEnabled() -> some View {
        #if os(visionOS)
        scrollInputBehavior(.enabled, for: .look)
        #else
        self
        #endif
    }

    @ViewBuilder
    func databaseASCIICapableKeyboard() -> some View {
        #if canImport(UIKit)
        keyboardType(.asciiCapable)
        #else
        self
        #endif
    }

    @ViewBuilder
    func databaseNoAutocapitalization() -> some View {
        #if canImport(UIKit)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func databaseWorkspaceWindowBackground() -> some View {
        #if os(macOS)
        containerBackground(.clear, for: .window)
        #else
        self
        #endif
    }

    /// Keeps the schema browser in Apple-provided material while the database
    /// canvas independently follows the user's opacity and blur settings.
    func databaseWorkspaceSidebarMaterial() -> some View {
        background(.regularMaterial)
    }

    @ViewBuilder
    func databaseWorkspaceWindowChrome(opensSidebarInitially: Bool = true) -> some View {
        #if os(macOS)
        background(MacDatabaseWorkspaceWindowReader(opensSidebarInitially: opensSidebarInitially))
        #else
        self
        #endif
    }

    /// Registers a window-scoped Command-W action with the macOS application
    /// dispatcher. The registration remains present while disabled so a
    /// database workspace never falls through to native Close Window.
    @ViewBuilder
    func databaseCommandWTarget(
        priority: DatabaseCommandWTargetPriority,
        isEnabled: Bool,
        perform action: @escaping @MainActor () -> Void
    ) -> some View {
        #if os(macOS)
        background {
            MacDatabaseCommandWTarget(
                priority: priority.rawValue,
                isEnabled: isEnabled,
                action: action
            )
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func databaseWorkspaceTabControlTarget() -> some View {
        #if os(macOS)
        frame(minWidth: 28, minHeight: 28)
        #else
        frame(minWidth: 44, minHeight: 44)
        #endif
    }

    @ViewBuilder
    func databaseSidebarChrome() -> some View {
        #if os(macOS)
        self
        #else
        toolbar(removing: .sidebarToggle)
        #endif
    }

    /// Structural contrast inside the live database canvas. Scaling by the
    /// user's paint opacity guarantees the surface disappears at 0%.
    func databaseCanvasSurface(opacity: Double, strength: Double = 0.06) -> some View {
        let alpha = DatabaseGlassAppearance(opacity: opacity, blur: 0)
            .surfaceAlpha(strength: strength)
        return background(Color.primary.opacity(alpha))
    }

    /// Appearance-aware backing for headers that remain fixed while database
    /// rows scroll beneath them. This intentionally strengthens intermediate
    /// values while still disappearing when both workspace controls are 0%.
    @ViewBuilder
    func databaseCanvasPinnedSurface(opacity: Double, blur: Double) -> some View {
        let appearance = DatabaseGlassAppearance(opacity: opacity, blur: blur)
        #if os(visionOS)
        background {
            ZStack {
                if appearance.compositesBlur {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(appearance.pinnedBlurAlpha)
                }
                Rectangle()
                    .fill(DatabaseCanvasPalette.background)
                    .opacity(appearance.pinnedSurfaceAlpha)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        #else
        background(DatabaseCanvasPalette.background.opacity(appearance.pinnedSurfaceAlpha))
        #endif
    }
}

enum DatabaseCommandWTargetPriority: Int {
    case workspace = 100
}

#if os(macOS)
@MainActor
final class MacDatabaseCommandWRouter: NSObject, NSMenuItemValidation {
    static let shared = MacDatabaseCommandWRouter()

    private static let semanticModifiers: NSEvent.ModifierFlags = [
        .command,
        .option,
        .control,
        .shift,
    ]

    private final class Registration {
        weak var window: NSWindow?
        var priority: Int
        var isEnabled: Bool
        var action: @MainActor () -> Void

        init(
            window: NSWindow?,
            priority: Int,
            isEnabled: Bool,
            action: @escaping @MainActor () -> Void
        ) {
            self.window = window
            self.priority = priority
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    private var registrations: [UUID: Registration] = [:]

    /// SwiftUI's macOS lifecycle owns the application object, so the reliable
    /// interception point is the File menu command that AppKit invokes for both
    /// its Command-W key equivalent and a direct menu selection.
    func installCloseCommandInterceptor(in mainMenu: NSMenu? = NSApp.mainMenu) {
        guard let closeItem = mainMenu.flatMap(Self.commandWItem) else { return }
        closeItem.target = self
        closeItem.action = #selector(performCloseCommand(_:))
    }

    func update(
        id: UUID,
        window: NSWindow?,
        priority: Int,
        isEnabled: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        if let registration = registrations[id] {
            registration.window = window
            registration.priority = priority
            registration.isEnabled = isEnabled
            registration.action = action
        } else {
            registrations[id] = Registration(
                window: window,
                priority: priority,
                isEnabled: isEnabled,
                action: action
            )
        }
        installCloseCommandInterceptor()
    }

    func remove(id: UUID) {
        registrations[id] = nil
    }

    /// Returns true when the target window belongs to a database workspace.
    /// Even with no enabled editor action, consuming Close prevents the
    /// permanent Overview/SQL workspace from being closed accidentally.
    func routeClose(targetWindow: NSWindow?) -> Bool {
        guard let targetWindow else { return false }
        registrations = registrations.filter { $0.value.window != nil }
        let windowRegistrations = registrations.values.filter {
            $0.window === targetWindow
        }
        guard !windowRegistrations.isEmpty else { return false }

        let action = windowRegistrations
            .filter(\.isEnabled)
            .max { $0.priority < $1.priority }?
            .action
        action?()
        return true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(performCloseCommand(_:))
            || NSApp.keyWindow != nil
    }

    @objc private func performCloseCommand(_ sender: NSMenuItem) {
        guard NSApp.currentEvent?.isARepeat != true else { return }
        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        guard !routeClose(targetWindow: targetWindow) else { return }
        targetWindow?.performClose(sender)
    }

    private static func commandWItem(in mainMenu: NSMenu) -> NSMenuItem? {
        mainMenu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { item in
                item.keyEquivalent.lowercased() == "w"
                    && item.keyEquivalentModifierMask
                        .intersection(semanticModifiers) == .command
                    && !item.isAlternate
            }
    }
}

struct MacDatabaseCommandWTarget: NSViewRepresentable {
    let priority: Int
    let isEnabled: Bool
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView(frame: .zero)
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(
            priority: priority,
            isEnabled: isEnabled,
            action: action
        )
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        context.coordinator.update(
            priority: priority,
            isEnabled: isEnabled,
            action: action
        )
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowReaderView, coordinator: Coordinator) {
        nsView.windowDidChange = nil
        coordinator.removeRegistration()
    }

    @MainActor
    final class Coordinator {
        private let id = UUID()
        private weak var window: NSWindow?
        private var priority = 0
        private var isEnabled = false
        private var action: @MainActor () -> Void = {}

        func attach(to window: NSWindow?) {
            self.window = window
            publish()
        }

        func update(
            priority: Int,
            isEnabled: Bool,
            action: @escaping @MainActor () -> Void
        ) {
            self.priority = priority
            self.isEnabled = isEnabled
            self.action = action
            publish()
        }

        func removeRegistration() {
            MacDatabaseCommandWRouter.shared.remove(id: id)
        }

        private func publish() {
            MacDatabaseCommandWRouter.shared.update(
                id: id,
                window: window,
                priority: priority,
                isEnabled: isEnabled,
                action: action
            )
        }
    }

    @MainActor
    final class WindowReaderView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

/// Uses AppKit's behind-window compositor without changing the opacity of SQL,
/// grid text, selection, or toolbar content.
struct MacDatabaseCanvasVisualEffect: NSViewRepresentable {
    let amount: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: .zero)
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        view.wantsLayer = true
        view.alphaValue = DatabaseGlassAppearance(opacity: 0, blur: amount).blur
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.state = .active
        nsView.alphaValue = DatabaseGlassAppearance(opacity: 0, blur: amount).blur
    }
}

typealias MacDatabaseWorkspaceTitlebarMaterialView = GlassTitlebarMaterialView

/// Reuses the sister app's proven AppKit window-reader pattern to preserve
/// native titlebar material around a transparent SwiftUI database canvas.
struct MacDatabaseWorkspaceWindowReader: NSViewRepresentable {
    var opensSidebarInitially = true

    func makeNSView(context: Context) -> NSView {
        let view = NonHitTestingWindowReaderView(frame: .zero)
        view.opensSidebarInitially = opensSidebarInitially
        view.scheduleConfiguration()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? NonHitTestingWindowReaderView else { return }
        view.opensSidebarInitially = opensSidebarInitially
        view.scheduleConfiguration()
    }

    @MainActor
    final class NonHitTestingWindowReaderView: NSView {
        var opensSidebarInitially = true
        private weak var configuredWindow: NSWindow?
        private var appliedInitialSidebar = false
        private var hasActivated = false

        deinit { NotificationCenter.default.removeObserver(self) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, configuredWindow !== window {
                NotificationCenter.default.removeObserver(self)
                configuredWindow = window
                appliedInitialSidebar = false
                hasActivated = window.isKeyWindow
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowDidBecomeKey(_:)),
                    name: NSWindow.didBecomeKeyNotification, object: window
                )
            }
            scheduleConfiguration()
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            guard !hasActivated else { return }
            hasActivated = true
            // Wait until initial native window presentation/restoration settles.
            // Later activations never reopen a sidebar the user has hidden.
            DispatchQueue.main.async { [weak self] in self?.applyInitialSidebarIfNeeded() }
        }

        func scheduleConfiguration() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                MacDatabaseWorkspaceWindowPolicy.apply(window)
                self.applyInitialSidebarIfNeeded()
            }
        }

        override func layout() {
            super.layout()
            applyInitialSidebarIfNeeded()
        }

        private func applyInitialSidebarIfNeeded() {
            guard hasActivated, opensSidebarInitially, !appliedInitialSidebar,
                  let root = window?.contentView else { return }
            var views = [root]
            var index = 0
            while index < views.count, index < 256 {
                let view = views[index]
                index += 1
                if let split = view as? NSSplitView,
                   let controller = split.delegate as? NSSplitViewController,
                   let sidebar = controller.splitViewItems.first(where: { $0.behavior == .sidebar }) {
                    // One initial native action, never an update-time toolbar mutation.
                    appliedInitialSidebar = true
                    sidebar.isCollapsed = false
                    return
                }
                views.append(contentsOf: view.subviews)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

@MainActor
enum MacDatabaseWorkspaceWindowPolicy {
    static func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        // Match glas.sh's `MacTerminalWindowPolicy` and Apple's full-height
        // sidebar windows: content extends under the toolbar, and SwiftUI's
        // NavigationSplitView places its per-column titlebar backgrounds in
        // that top band. Removing `.fullSizeContentView` pushed the split view
        // below the toolbar, so those 40pt titlebar backgrounds landed on top
        // of the workspace tab strip instead.
        // The window itself is clear, so AppKit draws no titlebar material of
        // its own; `installTitlebarMaterial` supplies it behind the band.
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.autorecalculatesKeyViewLoop = true
        // As in glas.sh, let the system choose toolbar style and control size.
        // The passive material must not impose compact window chrome.
        GlassWindowChrome.installTitlebarMaterial(in: window)
    }


}
#endif

// MARK: - Native command routing

/// Routes menu-bar commands to the focused database workspace. The workspace
/// is the single publisher of this value: every SQL tab stays alive hidden in
/// the workspace ZStack, and competing `focusedSceneValue` publishers resolve
/// focus-dependently, so per-editor publication goes dead as soon as a second
/// editor exists. Enablement flags are computed from workspace-owned document
/// state; editor-internal verbs delegate to the active tab's registered
/// `QueryEditorCommandHandlers`.
struct DatabaseWorkspaceCommandActions {
    let canExecute: Bool
    let canCancel: Bool
    let canSave: Bool
    let canUseQueryLibrary: Bool
    let canCloseTab: Bool
    let newQueryTab: () -> Void
    let closeTab: () -> Void
    let openDocument: () -> Void
    let saveDocument: () -> Void
    let executeStatement: () -> Void
    let executeScript: () -> Void
    let explainPlan: () -> Void
    let cancel: () -> Void
    let formatSQL: () -> Void
    let showHistory: () -> Void
    let showSavedQueries: () -> Void
    let runTitle: String
    let canRunSelection: Bool
    let executeSelection: () -> Void
    let executeCurrentStatement: () -> Void
}

/// Verbs only an individual SQL editor can perform (execution pipeline and
/// its presentation sheets). Each editor registers one bundle with its owning
/// workspace for its whole lifetime, keyed by document id; the workspace
/// consults only the active tab's bundle. Closures capture `@State` and
/// `@Binding` storage, so a single registration stays current.
struct QueryEditorCommandHandlers {
    let executeStatement: () -> Void
    let executeScript: () -> Void
    let explainPlan: () -> Void
    let cancel: () -> Void
    let showHistory: () -> Void
    let showSavedQueries: () -> Void
    let executeSelection: () -> Void
    let executeCurrentStatement: () -> Void
}

private struct DatabaseWorkspaceCommandActionsKey: FocusedValueKey {
    typealias Value = DatabaseWorkspaceCommandActions
}

extension FocusedValues {
    var databaseWorkspaceCommandActions: DatabaseWorkspaceCommandActions? {
        get { self[DatabaseWorkspaceCommandActionsKey.self] }
        set { self[DatabaseWorkspaceCommandActionsKey.self] = newValue }
    }
}

#if os(macOS)
@MainActor
final class MacDatabasePaletteCatalog {
    let sessionManager: DatabaseSessionManager
    let open: (UUID, WorkspaceSelection) -> Void
    private var databases: [UUID: [String]] = [:]
    private var tables: [UUID: [String: [String]]] = [:]

    init(sessionManager: DatabaseSessionManager, open: @escaping (UUID, WorkspaceSelection) -> Void) {
        self.sessionManager = sessionManager
        self.open = open
    }

    func entries(for query: String) async throws -> [MacCommandCenterEntry] {
        var result: [MacCommandCenterEntry] = []
        let query = query.lowercased()
        guard !query.hasPrefix("connect:") else { return result }
        for (id, session) in sessionManager.sessions.sorted(by: { $0.value.connectionConfig.name < $1.value.connectionConfig.name }) {
            guard session.state.isConnected, let connection = session.connection else { continue }
            let server = session.connectionConfig.name
            func entry(_ path: String, selection: WorkspaceSelection, expands: Bool) -> MacCommandCenterEntry {
                MacCommandCenterEntry(id: "catalog.\(id).\(path)", title: path,
                                     detail: "Connected database destination", completion: path + (expands ? "." : "")) {
                    guard self.sessionManager.sessions[id]?.state.isConnected == true else { NSSound.beep(); return }
                    self.open(id, selection)
                }
            }
            result.append(entry(server, selection: .connection, expands: true))
            guard query.hasPrefix(server.lowercased() + ".") else { continue }
            if databases[id] == nil { databases[id] = try await connection.databases() }
            try Task.checkCancellation()
            guard session.state.isConnected else { continue }
            for database in databases[id] ?? [] {
                let path = server + "." + database
                result.append(entry(path, selection: .database(database), expands: true))
                guard query.hasPrefix(path.lowercased() + ".") else { continue }
                if tables[id]?[database] == nil {
                    let names = try await connection.tables(in: database)
                    try Task.checkCancellation()
                    tables[id, default: [:]][database] = names
                }
                for table in tables[id]?[database] ?? [] {
                    result.append(entry(path + "." + table, selection: .table(database: database, table: table), expands: false))
                }
            }
        }
        return result
    }
}

struct DatabaseCommands: Commands {
    let connectionManager: ConnectionManager
    let sessionManager: DatabaseSessionManager
    @FocusedValue(\.macCommandCenterEntries) private var commandCenterEntries
    @FocusedValue(\.databaseWorkspaceCommandActions) private var workspaceActions
    @Environment(\.openWindow) private var openWindow

    private func presentCommandPalette() {
        let connections = connectionManager.connections.map { config in
            MacCommandCenterEntry(id: "connection.connect.\(config.id)", title: "connect: \(config.name)",
                                  detail: "Open a database connection window") {
                sessionManager.paletteConnectionRequest = config.id
                openWindow(id: "main")
            }
        }
        let catalog = MacDatabasePaletteCatalog(sessionManager: sessionManager) { id, selection in
            let request = DatabaseWorkspaceWindowRequest.additional(sessionID: id, initialSelection: selection)
            openWindow(id: "database-workspace", value: sessionManager.registerWorkspace(request))
        }
        GlassCommandPalette.present(
            additionalEntries: connections + (commandCenterEntries ?? []).filter { !$0.id.hasPrefix("connection.connect.") },
            destinations: { try await catalog.entries(for: $0) })
    }

    var body: some Commands {
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
        // File owns the SQL document lifecycle per the macOS HIG.
        //
        // **Added after, never replacing.** This group used to replace `.newItem`, to remove the
        // system-generated "New Connections Window ⌘N" that would otherwise capture ⌘N. In the
        // merged app the terminal's workspace commands replace that placement too — and SwiftUI
        // keeps one of two replacements, so replacing here silently deleted the whole terminal
        // File group from the menu bar (verified in the running app, 2026-09-16: ⌘T reached
        // nothing). The terminal's group is now the single replacement, which still removes the
        // generated item, and these are appended to it.
        CommandGroup(after: .newItem) {
            // No ⌘N here: ⌘N is the shell's one contextual New, and the workspace publishes
            // `\.glassNewItem` so that when a database workspace is focused ⌘N *is* this item
            // (`DatabaseWorkspaceView.swift`). Unbound here, it stays reachable from any window.
            Button("New SQL Document") { workspaceActions?.newQueryTab() }
                .disabled(workspaceActions == nil)
            Button("New Connections Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Open SQL Document…") { workspaceActions?.openDocument() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(workspaceActions == nil)

            Divider()

            Button("Close Active Tab") { workspaceActions?.closeTab() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(workspaceActions?.canCloseTab != true)
            Button("Save SQL Document…") { workspaceActions?.saveDocument() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(workspaceActions?.canSave != true)
        }

        CommandMenu("Query") {
            Button(workspaceActions?.runTitle ?? "Run Statement") { workspaceActions?.executeStatement() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(workspaceActions?.canExecute != true)
            Button("Run Statement at Cursor") { workspaceActions?.executeCurrentStatement() }
                .disabled(workspaceActions?.canExecute != true)
            Button("Run Selection") { workspaceActions?.executeSelection() }
                .disabled(workspaceActions?.canRunSelection != true)
            Button("Run All Statements") { workspaceActions?.executeScript() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(workspaceActions?.canExecute != true)
            Button("Explain Plan") { workspaceActions?.explainPlan() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(workspaceActions?.canExecute != true || workspaceActions?.canUseQueryLibrary != true)
            Button("Cancel Query") { workspaceActions?.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(workspaceActions?.canCancel != true)

            Divider()

            Button("Format SQL") { workspaceActions?.formatSQL() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(workspaceActions?.canExecute != true || workspaceActions?.canUseQueryLibrary != true)

            Divider()

            Button("Query History") { workspaceActions?.showHistory() }
                .disabled(workspaceActions?.canUseQueryLibrary != true)
            Button("Saved Queries") { workspaceActions?.showSavedQueries() }
                .disabled(workspaceActions?.canUseQueryLibrary != true)
        }
    }
}
#endif

#if os(macOS)
@MainActor let databaseToolbarPlacement: ToolbarItemPlacement = .automatic
@MainActor let databaseExecutionToolbarPlacement: ToolbarItemPlacement = .automatic
@MainActor let databaseTransferToolbarPlacement: ToolbarItemPlacement = .automatic
@MainActor let databaseContextToolbarPlacement: ToolbarItemPlacement = .automatic
@MainActor let databaseSidebarToolbarPlacement: ToolbarItemPlacement = .navigation
#elseif os(iOS)
@MainActor let databaseToolbarPlacement: ToolbarItemPlacement = .bottomBar
@MainActor let databaseExecutionToolbarPlacement: ToolbarItemPlacement = .primaryAction
@MainActor let databaseTransferToolbarPlacement: ToolbarItemPlacement = .bottomBar
@MainActor let databaseContextToolbarPlacement: ToolbarItemPlacement = .bottomBar
@MainActor let databaseSidebarToolbarPlacement: ToolbarItemPlacement = .topBarLeading
#else
@MainActor let databaseToolbarPlacement: ToolbarItemPlacement = .bottomOrnament
@MainActor let databaseExecutionToolbarPlacement: ToolbarItemPlacement = .primaryAction
@MainActor let databaseTransferToolbarPlacement: ToolbarItemPlacement = .bottomOrnament
@MainActor let databaseContextToolbarPlacement: ToolbarItemPlacement = .bottomOrnament
@MainActor let databaseSidebarToolbarPlacement: ToolbarItemPlacement = .topBarLeading
#endif

#if os(macOS)
/// Persistent workspace actions shared by every macOS database detail surface.
/// The active child places this content last so native toolbar spacers can keep
/// the group at the trailing edge without misusing modal action placements.
struct DatabasePersistentToolbar: ToolbarContent {
    let openSQL: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: databaseToolbarPlacement) {
            Button(action: openSQL) {
                Label("SQL Editor", systemImage: "text.page")
            }
            .help("Show the SQL editor")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings")
        }
    }
}
#endif

#if os(macOS)
/// Walks up to the hosting `NSSplitView` and gives it an autosave name, which
/// is what makes AppKit remember divider positions across launches. SwiftUI
/// exposes no equivalent for `NavigationSplitView`, so the attachment view is
/// invisible and never takes hit tests.

#endif
// The command palette lives in GlassLayers, so both capabilities contribute entries to one
// surface. A byte-for-byte copy of it used to sit here.
