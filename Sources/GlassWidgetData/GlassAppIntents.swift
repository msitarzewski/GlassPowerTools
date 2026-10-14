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
    case notReady

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noService(machine, kind):
            "\(machine) has no \(kind) service. Add one to it in Glass Power Tools."
        case .noFile:
            "The file could not be read. Choose it again, from a folder Glass Power Tools can open."
        case .notReady:
            "Glass Power Tools is still starting. Try again in a moment."
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

/// A saved query, opened in a new SQL tab on its database (D72). Not run: what it does to the data
/// is decided at the keyboard.
public struct GlassOpenSavedQueryIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Saved Query"
    public static let description = IntentDescription("Opens a saved query in a new SQL tab on its database, connecting first if needed. It is not run.")

    @Parameter(title: "Saved Query") public var target: GlassSavedQueryEntity

    public init() {}
    public init(target: GlassSavedQueryEntity) { self.target = target }

    @MainActor
    public func perform() async throws -> some IntentResult {
        GlassWidgetRequests.shared.post(.openSavedQuery(target.id))
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

// MARK: - Widgets

/// The Machine widget's one setting: which machine it shows.
public struct GlassMachineWidgetConfiguration: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Machine"
    public static let description = IntentDescription("Choose the machine this widget shows.")

    @Parameter(title: "Machine") public var machine: GlassMachineEntity?

    public init() {}
    public init(machine: GlassMachineEntity?) { self.machine = machine }
}

// MARK: - Sending files

/// What the app does for an intent that needs an answer back, rather than a window: set by the app
/// as it starts (`GlassWidgetBridge`). An intent that runs first waits for it, a little.
@MainActor
public final class GlassAppServices {
    public static let shared = GlassAppServices()

    /// Sends files to a machine's folder and says what happened.
    public typealias SendFiles = @MainActor (_ files: [URL], _ machine: UUID, _ folder: String?) async throws -> String

    public var sendFiles: SendFiles?

    public init() {}

    /// `sendFiles` once the app has set it — within `timeout`, or nil.
    func waitForSendFiles(timeout: Duration = .seconds(15)) async -> SendFiles? {
        let deadline = ContinuousClock.now + timeout
        while sendFiles == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return sendFiles
    }
}

/// Files to a folder on a machine (D72): the Files browser's verified upload, nothing on the machine
/// ever replaced. From Shortcuts — and so from the share sheet, through a shortcut that takes files —
/// on every platform.
public struct GlassSendFilesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Send Files to a Machine"
    public static let description = IntentDescription(
        "Sends files to a folder on a machine in your library. Nothing there is replaced: a name already taken gets a number.")
    public static let openAppWhenRun = true

    @Parameter(title: "Files", supportedContentTypes: [.item]) public var files: [IntentFile]
    @Parameter(title: "Machine") public var machine: GlassMachineEntity
    @Parameter(title: "Folder", description: "A folder on the machine, from its home folder; empty for the home folder itself.")
    public var folder: String?

    public static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$files) to \(\.$machine)") {
            \.$folder
        }
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard machine.service(.terminal) != nil else {
            throw GlassIntentError.noService(machine: machine.name, kind: GlassWidgetSnapshot.ServiceKind.terminal.title)
        }
        let local = try Self.localCopies(of: files)
        defer { if let staging = local.staging { try? FileManager.default.removeItem(at: staging) } }
        guard let send = await GlassAppServices.shared.waitForSendFiles() else { throw GlassIntentError.notReady }
        let summary = try await send(local.urls, machine.id, folder)
        return .result(value: summary, dialog: "\(summary)")
    }

    /// Each file as a file on this device: the one it names when it has one, or the bytes it carries
    /// written into a staging folder of their own, removed afterwards.
    static func localCopies(of files: [IntentFile]) throws -> (urls: [URL], staging: URL?) {
        var urls: [URL] = []
        var staging: URL?
        for (index, file) in files.enumerated() {
            if let url = file.fileURL, FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
                continue
            }
            let folder = try staging ?? {
                let made = FileManager.default.temporaryDirectory
                    .appendingPathComponent("glass-send-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
                staging = made
                return made
            }()
            let name = file.filename.isEmpty ? "file-\(index + 1)" : (file.filename as NSString).lastPathComponent
            let copy = folder.appendingPathComponent(name)
            try file.data.write(to: copy, options: [.atomic])
            urls.append(copy)
        }
        guard !urls.isEmpty else { throw GlassIntentError.noFile }
        return (urls, staging)
    }
}

#if !os(visionOS)
/// The Open Terminal control's one setting: which machine (D72). Control Center, the Mac's menu bar,
/// the Lock Screen and the iPhone's Action button; Vision Pro has no controls.
public struct GlassMachineControlConfiguration: ControlConfigurationIntent {
    public static let title: LocalizedStringResource = "Machine"
    public static let description = IntentDescription("Choose the machine this control opens a terminal on.")

    @Parameter(title: "Machine") public var machine: GlassMachineEntity?

    public init() {}
}

/// What the Open Terminal control runs: the chosen machine's terminal, or — none chosen yet — the
/// library, where one can be. One intent whatever the configuration, as a control's template has
/// no branches. Not offered in Shortcuts, which has Open Terminal itself.
public struct GlassOpenTerminalControlIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Terminal"
    public static let openAppWhenRun = true
    public static let isDiscoverable = false

    @Parameter(title: "Machine") public var machine: GlassMachineEntity?

    public init() {}
    public init(machine: GlassMachineEntity?) { self.machine = machine }

    @MainActor
    public func perform() async throws -> some IntentResult {
        if let machine {
            try GlassIntentConnect.open(.terminal, on: machine)
        } else {
            GlassWidgetRequests.shared.post(.showActive)
        }
        return .result()
    }
}
#endif
