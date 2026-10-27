//
//  FocusEnvironments.swift
//  Glass Power Tools — GlassTerminal
//
//  What surrounds the person in Focus Mode on Vision Pro (the owner, 2026-10-22: "the user should be
//  able to upload their own environment"; 2026-10-26: "build the upload interfaces and the
//  environment library"). Until then Focus Mode only dimmed the room.
//
//  The library is the built-in environments, drawn here in code (`FocusEnvironmentArt`), and the
//  person's own: 3D rooms (USDZ or Reality) and 360° photos (equirectangular, twice as wide as they
//  are tall). Their own are files in iCloud Drive ▸ Glass Power Tools ▸ Environments (his answer,
//  2026-10-22: "iCloud"), so a file put there from a Mac's Finder, or added on one headset, is in the
//  library everywhere. Without iCloud Drive they stay in this device's Application Support.
//
//  Settings ▸ Terminal ▸ Focus Mode chooses one for every window; This Window, and the moon's
//  pinch-and-hold menu, for one window (`TerminalWindowSettings.focusEnvironment`). An environment is
//  named by an identifier that means the same on every device: `builtin.<name>`, or `file:<name>`
//  for a file in the library's folder.
//

import Foundation
import Observation
import OSLog
import ImageIO
import UniformTypeIdentifiers
import GlassEditorCore

/// One of the environments Focus Mode can put around the person.
nonisolated struct FocusEnvironment: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Drawn here (`FocusEnvironmentArt`).
        case builtIn(FocusBuiltInEnvironment)
        /// A 360° photo: an equirectangular picture, wrapped around the person.
        case photo
        /// A 3D scene placed around the person, its floor at their feet.
        case room
    }

    /// What every window and device calls it (`builtin.<name>`, `file:<name>`).
    let id: String
    let name: String
    let kind: Kind
    /// The file, for one of the person's own.
    let file: URL?
    /// False while iCloud has only its name on this device.
    var isDownloaded = true

    /// Focus Mode as it always was: the room around the person, dimmed.
    static let defaultID = FocusBuiltInEnvironment.dimmed.id

    init(builtIn: FocusBuiltInEnvironment) {
        id = builtIn.id
        name = builtIn.title
        kind = .builtIn(builtIn)
        file = nil
    }

    init(id: String, name: String, kind: Kind, file: URL?, isDownloaded: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.file = file
        self.isDownloaded = isDownloaded
    }

    /// The person's own, which they can delete; the built-ins stay.
    var isOwn: Bool { file != nil }
}

/// The environments that come with the app.
nonisolated enum FocusBuiltInEnvironment: String, CaseIterable, Sendable {
    case dimmed, nightSky, dusk, grid, studio

    var id: String { "builtin.\(rawValue)" }

    var title: String {
        switch self {
        case .dimmed: "Dimmed Room"
        case .nightSky: "Night Sky"
        case .dusk: "Dusk"
        case .grid: "Grid"
        case .studio: "Studio"
        }
    }

    init?(id: String) {
        guard id.hasPrefix("builtin.") else { return nil }
        self.init(rawValue: String(id.dropFirst("builtin.".count)))
    }
}

/// The library's files, by name: which are environments, what each is called, and the names new
/// ones are given. Pure, so it is tested without iCloud.
nonisolated enum FocusEnvironmentFiles {
    static let roomExtensions: Set<String> = ["usdz", "reality"]
    static let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
    static let idPrefix = "file:"
    /// The longest identifier a window keeps: a file name's 255 bytes and the prefix.
    static let longestID = 300

    struct Entry: Equatable {
        /// The file's own name, which its identifier carries.
        let fileName: String
        /// Its name without the extension, as the library shows it.
        let name: String
        let kind: FocusEnvironment.Kind
        /// False for iCloud's stand-in for a file not yet on this device.
        let isDownloaded: Bool
    }

    /// The environment a file in the library's folder is, or nil for any other file. iCloud keeps a
    /// file that isn't on this device yet as `.Room.usdz.icloud`: that is the file `Room.usdz`.
    static func entry(named fileName: String) -> Entry? {
        var name = fileName
        var downloaded = true
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            name = String(name.dropFirst().dropLast(".icloud".count))
            downloaded = false
        }
        guard !name.hasPrefix("."), let kind = kind(of: name) else { return nil }
        let shown = (name as NSString).deletingPathExtension
        return Entry(fileName: name, name: shown.isEmpty ? name : shown, kind: kind, isDownloaded: downloaded)
    }

    /// A room or a photo, by the file's extension; nil for anything else.
    static func kind(of fileName: String) -> FocusEnvironment.Kind? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if roomExtensions.contains(ext) { return .room }
        if photoExtensions.contains(ext) { return .photo }
        return nil
    }

    static func id(forFileNamed fileName: String) -> String { idPrefix + fileName }

    /// The file an identifier names, or nil for a built-in or one that can't be a file's.
    static func fileName(fromID id: String) -> String? {
        guard id.hasPrefix(idPrefix), id.count <= longestID else { return nil }
        let name = String(id.dropFirst(idPrefix.count))
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."), name != ".." else { return nil }
        return name
    }

    /// Whether a window may keep `id`: a built-in's, or one a file could have.
    static func isValidID(_ id: String) -> Bool {
        FocusBuiltInEnvironment(id: id) != nil || fileName(fromID: id) != nil
    }

    /// A name for an added file that the library doesn't have yet: its own, else "Room 2.usdz",
    /// "Room 3.usdz"… The extension is lowercased, and a path's slashes can't reach the name.
    static func availableName(for fileName: String, taken: Set<String>) -> String {
        let flat = fileName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var base = (flat as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        var ext = (flat as NSString).pathExtension.lowercased()
        // ".usdz" is all extension.
        if ext.isEmpty, flat.hasPrefix(".") { ext = String(flat.dropFirst()).lowercased(); base = "" }
        let stem = base.isEmpty || base.hasPrefix(".") ? "Environment" : base
        let lowered = Set(taken.map { $0.lowercased() })
        var candidate = "\(stem).\(ext)"
        var number = 2
        while lowered.contains(candidate.lowercased()) {
            candidate = "\(stem) \(number).\(ext)"
            number += 1
        }
        return candidate
    }

    /// Whether a picture this size is a 360° photo: twice as wide as it is tall, within 2%.
    static func isEquirectangular(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        return abs(Double(width) / Double(height) - 2) <= 0.04
    }
}

/// Where a 3D file stands in Focus Mode. A room — wider than `roomWidth` — goes around the person,
/// its floor at their feet and its middle where they stand. Anything smaller would be around their
/// feet, or around them and unseen from inside (Apple's iMac model was, 2026-10-26), so it stands on
/// the floor ahead of them instead.
nonisolated enum FocusRoomPlacement {
    static let roomWidth: Float = 2.5
    /// How far ahead an object's near side stands.
    static let objectDistance: Float = 1.5

    /// The offset that places a model with these bounds, in metres; the person stands at the origin,
    /// facing −Z, on the floor at y = 0.
    static func offset(min: SIMD3<Float>, max: SIMD3<Float>) -> SIMD3<Float> {
        let center = (min + max) / 2, size = max - min
        guard size.x.isFinite, size.y.isFinite, size.z.isFinite else { return .zero }
        if isRoom(min: min, max: max) {
            return [-center.x, -min.y, -center.z]
        }
        return [-center.x, -min.y, -(objectDistance + size.z / 2) - center.z]
    }

    static func isRoom(min: SIMD3<Float>, max: SIMD3<Float>) -> Bool {
        let size = max - min
        return !size.x.isFinite || !size.z.isFinite || Swift.max(size.x, size.z) >= roomWidth
    }

    /// What the person is told about one that isn't a room, so it is never just missing.
    static func objectNote(name: String, min: SIMD3<Float>, max: SIMD3<Float>) -> String? {
        guard !isRoom(min: min, max: max) else { return nil }
        let across = Swift.max(max.x - min.x, max.z - min.z)
        let size = across >= 1 ? String(format: "%.1f m", across) : "\(Int((across * 100).rounded())) cm"
        return "“\(name)” is \(size) across, smaller than a room, so it stands on the floor ahead of you. To make it bigger, use Try Out in Settings ▸ Terminal ▸ Focus Mode."
    }
}

/// Why a file can't be added to the library, in words (`error-messages-say-the-fix`).
nonisolated enum FocusEnvironmentImportProblem: Error, Equatable {
    case notAnEnvironment(String)
    case notA360Photo(String, width: Int, height: Int)
    case unreadable(String)
    case notAModel(String)
    case copyFailed(String)

    var message: String {
        switch self {
        case .notAnEnvironment(let name):
            "“\(name)” isn't a 3D room or a 360° photo. Add a USDZ or Reality file, or a picture twice as wide as it is tall."
        case .notA360Photo(let name, let width, let height):
            "“\(name)” isn't a 360° photo: it's \(width) × \(height), and a 360° photo is twice as wide as it is tall."
        case .unreadable(let name):
            "“\(name)” couldn't be read. Check that it has finished downloading, then add it again."
        case .notAModel(let name):
            "“\(name)” is named like a 3D file but isn't one inside. Export it again as USDZ, then add it."
        case .copyFailed(let name):
            "“\(name)” couldn't be copied into your environments. Check that there's space in iCloud Drive, then add it again."
        }
    }
}

/// The library: the built-ins, then the person's own by name, kept current as files come and go.
@Observable
final class FocusEnvironmentLibrary {
    static let shared = FocusEnvironmentLibrary()

    enum Storage: Equatable {
        /// Still asking iCloud where its folder is.
        case finding
        /// iCloud Drive ▸ Glass Power Tools ▸ Environments.
        case iCloud
        /// This device only: iCloud Drive is off, or the app can't reach it.
        case device
    }

    private(set) var environments: [FocusEnvironment] = FocusBuiltInEnvironment.allCases.map(FocusEnvironment.init(builtIn:))
    private(set) var storage: Storage = .finding

    @ObservationIgnored private var cloudFolder: URL?
    @ObservationIgnored private var deviceFolder: URL?
    /// Where each 3D file's fit is kept (`FocusRoomFit`), under its file's name. iCloud's is in the
    /// app's container beside Documents, so it travels with the files but isn't shown in Files.
    @ObservationIgnored private var cloudFits: URL?
    @ObservationIgnored private var deviceFits: URL?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    nonisolated private static let log = Logger(subsystem: "com.glasspowertools", category: "FocusEnvironments")

    /// Folders given here instead of iCloud's and the device's, for tests.
    init(cloudFolder: URL? = nil, deviceFolder: URL? = nil) {
        if cloudFolder != nil || deviceFolder != nil {
            self.cloudFolder = cloudFolder
            self.deviceFolder = deviceFolder
            cloudFits = cloudFolder.map { $0.deletingLastPathComponent().appendingPathComponent("Environment Fits", isDirectory: true) }
            deviceFits = deviceFolder.map { $0.deletingLastPathComponent().appendingPathComponent("Focus Environment Fits", isDirectory: true) }
            storage = cloudFolder == nil ? .device : .iCloud
            started = true
            refresh()
        }
    }

    /// Finds the folders, once, and lists them; iCloud's is watched for files from other devices.
    func start() {
        guard !started else { return }
        started = true
        deviceFolder = Self.makeDeviceFolder()
        deviceFits = deviceFolder?.deletingLastPathComponent().appendingPathComponent("Focus Environment Fits", isDirectory: true)
        Task {
            // iCloud's container must not be asked for on the main thread.
            let cloud = await Task.detached(priority: .utility) { Self.makeCloudFolder() }.value
            cloudFolder = cloud
            // The container: Documents/Environments is two folders in.
            cloudFits = cloud?.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Environment Fits", isDirectory: true)
            #if DEBUG && os(visionOS)
            if ProcessInfo.processInfo.arguments.contains("--demo-environment-room"), let folder = cloud ?? deviceFolder {
                await FocusDemoRoom.make(in: folder)
            }
            #endif
            storage = cloud == nil ? .device : .iCloud
            refresh()
            if cloud != nil { watchCloud() }
        }
        refresh()
    }

    /// Until the library knows where its folders are, for a few seconds at most: one of the person's
    /// own asked for as the app starts isn't listed before then.
    func ready() async {
        for _ in 0..<50 where storage == .finding {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The environment an identifier names, if the library has it.
    func environment(withID id: String) -> FocusEnvironment? {
        environments.first { $0.id == id }
    }

    /// What the library calls an identifier, even one not on this device: "Room", for `file:Room.usdz`.
    func name(ofID id: String) -> String {
        if let environment = environment(withID: id) { return environment.name }
        if let builtIn = FocusBuiltInEnvironment(id: id) { return builtIn.title }
        if let file = FocusEnvironmentFiles.fileName(fromID: id) { return (file as NSString).deletingPathExtension }
        return id
    }

    /// Lists the folders again.
    func refresh() {
        var own: [String: FocusEnvironment] = [:]
        // The device's first, so iCloud's copy of a name wins.
        for folder in [deviceFolder, cloudFolder].compactMap({ $0 }) {
            for environment in Self.list(folder) { own[environment.id] = environment }
        }
        let sorted = own.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let next = FocusBuiltInEnvironment.allCases.map(FocusEnvironment.init(builtIn:)) + sorted
        if next != environments { environments = next }
    }

    /// Copies files into the library, each checked first: a 3D file must be one inside, a picture a
    /// 360° photo. Returns what couldn't be added, in words; the rest are in the library.
    @discardableResult
    func add(_ urls: [URL]) async -> [FocusEnvironmentImportProblem] {
        guard let folder = cloudFolder ?? deviceFolder else { return urls.map { .copyFailed($0.lastPathComponent) } }
        var problems: [FocusEnvironmentImportProblem] = []
        var taken = Set(environments.compactMap { $0.file?.lastPathComponent })
        for url in urls {
            let name = FocusEnvironmentFiles.availableName(for: url.lastPathComponent, taken: taken)
            let destination = folder.appendingPathComponent(name)
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.copyChecked(url, to: destination)
            }.value
            if let problem = outcome {
                problems.append(problem)
            } else {
                taken.insert(name)
            }
        }
        refresh()
        return problems
    }

    /// Deletes one of the person's own, and its fit, from every device that shares the folder.
    func remove(_ environment: FocusEnvironment) {
        guard let file = environment.file else { return }
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forDeleting, error: nil) { url in
            do { try FileManager.default.removeItem(at: url) } catch { failure = error }
        }
        if let failure { Self.log.error("Deleting a focus environment failed: \(failure.localizedDescription, privacy: .public)") }
        if let fitFile = fitFile(for: environment) { Self.deleteFit(fitFile) }
        refresh()
    }

    // MARK: - Fits

    /// Where a 3D file's fit is kept: in the fits folder beside its library folder, under its name.
    func fitFile(for environment: FocusEnvironment) -> URL? {
        guard let file = environment.file else { return nil }
        let inCloud = file.deletingLastPathComponent().standardizedFileURL.path == cloudFolder?.standardizedFileURL.path
        return (inCloud ? cloudFits : deviceFits)?.appendingPathComponent(file.lastPathComponent + ".json")
    }

    /// The fit kept for a 3D file, if there is one; read off the main thread, as iCloud may fetch it.
    func fit(for environment: FocusEnvironment) async -> FocusRoomFit? {
        guard let file = fitFile(for: environment) else { return nil }
        return await Task.detached(priority: .userInitiated) { Self.readFit(file) }.value
    }

    /// Keeps a fit beside its file; a fit that changes nothing is no file at all.
    func save(_ fit: FocusRoomFit, for environment: FocusEnvironment) async {
        guard let file = fitFile(for: environment) else { return }
        await Task.detached(priority: .userInitiated) {
            if fit == FocusRoomFit() { Self.deleteFit(file) } else { Self.writeFit(fit, to: file) }
        }.value
    }

    nonisolated private static func readFit(_ file: URL) -> FocusRoomFit? {
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: nil) { url in
            data = try? Data(contentsOf: url)
        }
        return data.flatMap(FocusRoomFit.decoded(from:))
    }

    nonisolated private static func writeFit(_ fit: FocusRoomFit, to file: URL) {
        guard let data = fit.encoded() else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            log.error("The fits folder couldn't be made: \(error.localizedDescription, privacy: .public)")
            return
        }
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: nil) { url in
            do { try data.write(to: url, options: .atomic) } catch { failure = error }
        }
        if let failure { log.error("A fit couldn't be kept: \(failure.localizedDescription, privacy: .public)") }
    }

    nonisolated private static func deleteFit(_ file: URL) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forDeleting, error: nil) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Asks iCloud for a file that isn't on this device yet.
    func download(_ environment: FocusEnvironment) {
        guard let file = environment.file, !environment.isDownloaded else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: file)
        } catch {
            Self.log.error("Downloading a focus environment failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Folders

    nonisolated private static func makeDeviceFolder() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent("com.glasspowertools/Focus Environments", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// iCloud Drive ▸ Glass Power Tools ▸ Environments: the container's Documents, which iCloud Drive
    /// shows under the app's name (`NSUbiquitousContainers` in Info.plist).
    nonisolated private static func makeCloudFolder() -> URL? {
        #if os(visionOS)
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let folder = container.appendingPathComponent("Documents/Environments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            log.error("iCloud's environments folder couldn't be made: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return folder
        #else
        // Only Vision Pro has Focus Mode's environments; other devices reach the folder in Files.
        return nil
        #endif
    }

    nonisolated private static func list(_ folder: URL) -> [FocusEnvironment] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { fileName in
            guard let entry = FocusEnvironmentFiles.entry(named: fileName) else { return nil }
            let file = folder.appendingPathComponent(entry.fileName)
            var downloaded = entry.isDownloaded
            if downloaded, let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus {
                downloaded = status == .current || status == .downloaded
            }
            return FocusEnvironment(id: FocusEnvironmentFiles.id(forFileNamed: entry.fileName), name: entry.name,
                                    kind: entry.kind, file: file, isDownloaded: downloaded)
        }
    }

    /// Files arriving from other devices, and downloads finishing, list the folder again.
    private func watchCloud() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        query.start()
        self.query = query
    }

    // MARK: - Adding

    /// Copies `source` to `destination` if it is an environment, or says why not.
    nonisolated private static func copyChecked(_ source: URL, to destination: URL) -> FocusEnvironmentImportProblem? {
        let name = source.lastPathComponent
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let kind = FocusEnvironmentFiles.kind(of: name) else { return .notAnEnvironment(name) }
        switch kind {
        case .room:
            guard let handle = try? FileHandle(forReadingFrom: source) else { return .unreadable(name) }
            let head = (try? handle.read(upToCount: GlassEditorFileKind.sniffLength)) ?? Data()
            try? handle.close()
            guard GlassEditorFileKind.classify(name: name, prefix: head) == .model3D else { return .notAModel(name) }
        case .photo:
            guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return .unreadable(name) }
            guard FocusEnvironmentFiles.isEquirectangular(width: width, height: height) else {
                return .notA360Photo(name, width: width, height: height)
            }
        case .builtIn:
            return .notAnEnvironment(name)
        }
        var failure: Error?
        var coordination: NSError?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordination) { url in
            do { try FileManager.default.copyItem(at: source, to: url) } catch { failure = error }
        }
        if let error = failure ?? coordination {
            log.error("Copying a focus environment failed: \(error.localizedDescription, privacy: .public)")
            return .copyFailed(name)
        }
        return nil
    }
}
