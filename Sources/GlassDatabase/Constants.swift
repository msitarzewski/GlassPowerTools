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
            openWindow(id: "query-editor", value: sessionManager.registerWorkspace(request))
        }
        MacCommandCenter.shared.present(
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
        // File owns the SQL document lifecycle per the macOS HIG. Replacing
        // .newItem removes the system-generated "New Connections Window ⌘N"
        // for the primary WindowGroup, which otherwise captures ⌘N before the
        // Query menu can see it.
        CommandGroup(replacing: .newItem) {
            Button("New SQL Document") { workspaceActions?.newQueryTab() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(workspaceActions == nil)
            Button("New Connections Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .newItem) {
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
#if os(macOS)
/// Snapshot of an existing action; opening the palette never executes commands.
@MainActor
struct MacCommandCenterEntry: Identifiable {
    let id: String
    let title: String
    let detail: String
    var shortcut: String = ""
    var isEnabled = true
    var completion: String? = nil
    let action: () -> Void

    static func matches(_ query: String, title: String, detail: String) -> Bool {
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

extension FocusedValues {
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
#endif
