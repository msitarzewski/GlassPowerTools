//
//  GlassWidgetIntents.swift
//  Glass Power Tools — GlassWidgetData
//
//  What a tap on a widget asks the app to do: connect to one of a machine's services, show a
//  machine in the library, or show Active. App Intents, defined here once for the app and the
//  widget extension both; each opens the app and runs there, where `GlassWidgetRequests` hands
//  the request to whoever the app has set to carry it out.
//
//  The widget before these had no tap of its own: its `glassh://` link went with the old apps'
//  URL schemes (D4), and a tap only launched the app.
//

import AppIntents
import Foundation

/// What a widget, Shortcuts, Siri or the Finder asks the app for (D72): every intent is carried out
/// in the app, through `GlassWidgetRequests`. Codable, so an extension in another process — a
/// Finder toolbar button, a Quick Action — can leave one for the app (`GlassExternalRequests`).
public enum GlassWidgetRequest: Sendable, Equatable, Codable {
    case connect(machine: UUID, service: UUID)
    case showMachine(UUID)
    case showActive
    /// All Windows: the Mac's Show All Windows, the pane on iPhone and iPad, the sheet on Vision
    /// Pro (the owner, 2026-10-14: "A Siri action on visionOS").
    case showAllWindows
    case openWorkgroup(UUID)
    /// A database's saved query, in a new SQL tab on its database — connected first when it is not.
    case openSavedQuery(UUID)
    /// The Mac: a terminal window here, in `folder` when there is one.
    case newLocalTerminal(folder: URL?)
    /// The Mac: a tab in the terminal window in front, in `folder` — a window when there is none.
    case newLocalTerminalTab(folder: URL)
    /// The Mac: a script (`.command`) run in a new tab, as Terminal runs one.
    case runInTerminal(URL)
    /// Files and folders into the editor: a folder opens as a project.
    case openInEditor([URL])
    /// An `ssh://` link: a saved machine connects; another fills in the new-server form.
    case openSSHLink(URL)
    /// A service continued from another device (Handoff): the machine that owns it, connected —
    /// for a terminal in tmux, in that session: the tab showing it, or one attached to it.
    case continueSession(endpoint: UUID, tmux: String?)
    /// The Mac's share extension (D72, the owner chose "mac only"): files copied into the App Group,
    /// to send to a folder on a machine; the copies go once they are sent.
    case sendFiles([URL], machine: UUID, folder: String?)
    /// Terminal profiles (`.terminal`) opened with the app — Open With, AirDrop, Files — into the
    /// terminal's Terminal Themes (2026-10-28); one alone becomes what All Terminals use.
    case importTerminalThemes([URL])

    /// What opening `url` with the app asks for — the Finder's Open With, a folder or script dropped
    /// on the Dock icon, a link (D72): an `ssh://` link connects; a Terminal profile becomes a terminal
    /// theme; on the Mac a folder opens a terminal there and a `.command` script runs in one; anything
    /// else goes to the editor. Nil for a link the app does not handle.
    public static func forOpened(_ url: URL, isMac: Bool) -> GlassWidgetRequest? {
        if url.scheme?.lowercased() == "ssh" { return .openSSHLink(url) }
        guard url.isFileURL else { return nil }
        if url.pathExtension.lowercased() == "terminal" { return .importTerminalThemes([url]) }
        if isMac {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
            let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
            if isFolder && !isPackage { return .newLocalTerminal(folder: url) }
            if url.pathExtension.lowercased() == "command" { return .runInTerminal(url) }
        }
        return .openInEditor([url])
    }
}

/// Requests from the widgets, in the app's process. One that arrives before the app has set its
/// handler — the app was launched for it — waits until it does.
@MainActor
public final class GlassWidgetRequests {
    public static let shared = GlassWidgetRequests()

    private var pending: [GlassWidgetRequest] = []
    private var handler: ((GlassWidgetRequest) -> Void)?

    public init() {}

    public func post(_ request: GlassWidgetRequest) {
        if let handler { handler(request) } else { pending.append(request) }
    }

    /// Sets who carries requests out, and gives them any that were waiting.
    public func handle(with handler: @escaping (GlassWidgetRequest) -> Void) {
        self.handler = handler
        let waiting = pending
        pending = []
        waiting.forEach(handler)
    }
}

/// Connect to one of a machine's services, as its row's service button in the library does.
public struct GlassConnectServiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Connect to a Service"
    public static let description = IntentDescription("Opens one of a machine's services in Glass Power Tools.")
    public static let openAppWhenRun = true
    /// From a widget only: Shortcuts has no way to choose a machine or service yet.
    public static let isDiscoverable = false

    @Parameter(title: "Machine") public var machine: String
    @Parameter(title: "Service") public var service: String

    public init() {}

    public init(machine: UUID, service: UUID) {
        self.machine = machine.uuidString
        self.service = service.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let machine = UUID(uuidString: machine), let service = UUID(uuidString: service) {
            GlassWidgetRequests.shared.post(.connect(machine: machine, service: service))
        }
        return .result()
    }
}

/// Show a machine in the library.
public struct GlassShowMachineIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show a Machine"
    public static let description = IntentDescription("Shows a machine in the Glass Power Tools library.")
    public static let openAppWhenRun = true
    public static let isDiscoverable = false

    @Parameter(title: "Machine") public var machine: String

    public init() {}

    public init(machine: UUID) {
        self.machine = machine.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let machine = UUID(uuidString: machine) { GlassWidgetRequests.shared.post(.showMachine(machine)) }
        return .result()
    }
}

/// Show Active: what is open, and what is running on machines.
public struct GlassShowActiveIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Active Connections"
    public static let description = IntentDescription("Shows what is open and running in Glass Power Tools.")
    public static let openAppWhenRun = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        GlassWidgetRequests.shared.post(.showActive)
        return .result()
    }
}

/// Show All Windows: what is open, as pictures.
public struct GlassShowAllWindowsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show All Windows"
    public static let description = IntentDescription("Shows everything open in Glass Power Tools, as pictures.")
    public static let openAppWhenRun = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        GlassWidgetRequests.shared.post(.showAllWindows)
        return .result()
    }
}

/// The intents above, for the app and the widget extension to include (`AppIntentsPackage`).
public struct GlassWidgetIntents: AppIntentsPackage {}
