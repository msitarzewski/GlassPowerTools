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
/// in the app, through `GlassWidgetRequests`.
public enum GlassWidgetRequest: Sendable, Equatable {
    case connect(machine: UUID, service: UUID)
    case showMachine(UUID)
    case showActive
    case openWorkgroup(UUID)
    /// The Mac: a terminal window here, in `folder` when there is one.
    case newLocalTerminal(folder: URL?)
    /// Files and folders into the editor: a folder opens as a project.
    case openInEditor([URL])
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

/// The intents above, for the app and the widget extension to include (`AppIntentsPackage`).
public struct GlassWidgetIntents: AppIntentsPackage {}
