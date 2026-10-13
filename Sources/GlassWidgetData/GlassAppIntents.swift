//
//  GlassAppIntents.swift
//  Glass Power Tools — GlassWidgetData
//
//  What Siri, Shortcuts, Spotlight and the widgets can ask Glass Power Tools to do, on every platform
//  (D72, 2026-10-13: "App intents, all of the modern stuff … Be sure visionOS is well represented!").
//  Each opens the app and is carried out there, through `GlassWidgetRequests`, the way the library
//  itself does it: a connection asks for host trust as usual, and on Vision Pro a session opens in a
//  window of its own in the room, as it does from the library.
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Why an intent could not do what it was asked, in words that say what to do.
public enum GlassIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noService(machine: String, kind: String)
    case noFile

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noService(machine, kind):
            "\(machine) has no \(kind) service. Add one to it in Glass Power Tools."
        case .noFile:
            "The file could not be read. Choose it again, from a folder Glass Power Tools can open."
        }
    }
}

// MARK: - Connecting

/// A terminal on a machine, as its row's terminal button opens one.
public struct GlassOpenTerminalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Terminal"
    public static let description = IntentDescription("Opens a terminal on a machine in your library.")
    public static let openAppWhenRun = true

    @Parameter(title: "Machine") public var machine: GlassMachineEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Open a terminal on \(\.$machine)")
    }

    public init() {}
    public init(machine: GlassMachineEntity) { self.machine = machine }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try GlassIntentConnect.open(.terminal, on: machine)
        return .result()
    }
}

/// A machine's remote desktop.
public struct GlassOpenDesktopIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Desktop"
    public static let description = IntentDescription("Opens a machine's remote desktop.")
    public static let openAppWhenRun = true

    @Parameter(title: "Machine") public var machine: GlassMachineEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Open the desktop of \(\.$machine)")
    }

    public init() {}
    public init(machine: GlassMachineEntity) { self.machine = machine }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try GlassIntentConnect.open(.desktop, on: machine)
        return .result()
    }
}

/// Any one of a machine's services — a database, most often, since a machine may have several.
public struct GlassOpenServiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Service"
    public static let description = IntentDescription("Opens a terminal, database or desktop from your library.")
    public static let openAppWhenRun = true

    @Parameter(title: "Service") public var service: GlassServiceEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$service)")
    }

    public init() {}
    public init(service: GlassServiceEntity) { self.service = service }

    @MainActor
    public func perform() async throws -> some IntentResult {
        GlassWidgetRequests.shared.post(.connect(machine: service.machineID, service: service.id))
        return .result()
    }
}

@MainActor
enum GlassIntentConnect {
    static func open(_ kind: GlassWidgetSnapshot.ServiceKind, on machine: GlassMachineEntity) throws {
        guard let service = machine.service(kind) else {
            throw GlassIntentError.noService(machine: machine.name, kind: kind.title)
        }
        GlassWidgetRequests.shared.post(.connect(machine: machine.id, service: service.id))
    }
}

// MARK: - Showing

/// A machine in the library. An open intent, so a machine found in search opens here.
public struct GlassOpenMachineIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Show Machine"
    public static let description = IntentDescription("Shows a machine and its services in your library.")

    @Parameter(title: "Machine") public var target: GlassMachineEntity

    public init() {}
    public init(target: GlassMachineEntity) { self.target = target }

    @MainActor
    public func perform() async throws -> some IntentResult {
        GlassWidgetRequests.shared.post(.showMachine(target.id))
        return .result()
    }
}

/// A saved workgroup: its terminals, opened together.
public struct GlassOpenWorkgroupIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Workgroup"
    public static let description = IntentDescription("Opens every terminal in a saved workgroup.")

    @Parameter(title: "Workgroup") public var target: GlassWorkgroupEntity

    public init() {}
    public init(target: GlassWorkgroupEntity) { self.target = target }

    @MainActor
    public func perform() async throws -> some IntentResult {
        GlassWidgetRequests.shared.post(.openWorkgroup(target.id))
        return .result()
    }
}

// MARK: - Files

/// Files and folders into the editor; a folder opens as a project.
public struct GlassOpenInEditorIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open in Editor"
    public static let description = IntentDescription("Opens files in the Glass Power Tools editor. A folder opens as a project.")
    public static let openAppWhenRun = true

    @Parameter(title: "Files", supportedContentTypes: [.item, .folder]) public var files: [IntentFile]

    public static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$files) in the editor")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let urls = files.compactMap(\.fileURL)
        guard !urls.isEmpty else { throw GlassIntentError.noFile }
        GlassWidgetRequests.shared.post(.openInEditor(urls))
        return .result()
    }
}

#if os(macOS)
/// A terminal window on this Mac, in a folder when one is given — a file stands for its folder.
public struct GlassNewTerminalIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Terminal Window"
    public static let description = IntentDescription("Opens a terminal window on this Mac, in a folder when you choose one.")
    public static let openAppWhenRun = true

    @Parameter(title: "Folder", supportedContentTypes: [.folder, .item]) public var folder: IntentFile?

    public static var parameterSummary: some ParameterSummary {
        Summary("New terminal window in \(\.$folder)")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        GlassWidgetRequests.shared.post(.newLocalTerminal(folder: folder?.fileURL))
        return .result()
    }
}
#endif
