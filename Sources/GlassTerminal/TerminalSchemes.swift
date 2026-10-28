//
//  TerminalSchemes.swift
//  Glass Power Tools — GlassTerminal
//
//  The person's own color schemes (the owner, 2026-10-28, for a user with a folder of 148: "Let's
//  make these work, first class style!"): Terminal profiles (`.terminal`) kept in iCloud Drive ▸
//  Glass Power Tools ▸ Terminal Themes, so every device that shares it has them, put there from
//  Settings ▸ Terminal ▸ Choose Theme ▸ Import or in Files and the Finder. Any number: a file each,
//  not the synced theme library, whose one key-value entry shares iCloud's 1 MB with workgroups,
//  projects and favorites.
//
//  A scheme is chosen for All Terminals or for one window by an identifier made from its file's
//  name (`TerminalSchemeFiles.id`), so the same file is the same scheme on every device; the choice
//  syncs with the terminal's settings, and a device without the file yet draws with your theme
//  until it comes. A scheme brings its colors, background included; the font stays yours.
//

import Foundation
import CryptoKit
import OSLog

nonisolated enum TerminalSchemeFiles {
    static let folderName = "Terminal Themes"
    static let fileExtension = "terminal"

    /// The same name is the same identifier on every device: a name-based UUID (version 5's
    /// layout, SHA-256 rather than SHA-1).
    static func id(forFileNamed fileName: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(("terminal-scheme:" + fileName.precomposedStringWithCanonicalMapping).utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// A scheme's file name from a folder's listing, and whether it is on this device: iCloud lists
    /// one still to come as `.Name.terminal.icloud`. Nil for anything else.
    static func entry(named listed: String) -> (fileName: String, isDownloaded: Bool)? {
        var name = listed
        var downloaded = true
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            name = String(name.dropFirst().dropLast(".icloud".count))
            downloaded = false
        }
        guard !name.hasPrefix("."), (name as NSString).pathExtension.lowercased() == fileExtension,
              !(name as NSString).deletingPathExtension.isEmpty else { return nil }
        return (name, downloaded)
    }
}

/// One scheme in the folder.
struct TerminalScheme: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let file: URL
    var isDownloaded: Bool
    /// Its colors over the built-in theme; nil until it has been read, or if it can't be.
    var theme: TerminalTheme?
    /// Why it can't be used, in words.
    var problem: String?

    /// Its file's name, which is what Files and the Finder show.
    var name: String { (fileName as NSString).deletingPathExtension }
}

@Observable
final class TerminalSchemeLibrary {
    static let shared = TerminalSchemeLibrary()

    enum Storage: Equatable {
        case finding
        /// iCloud Drive ▸ Glass Power Tools ▸ Terminal Themes.
        case iCloud
        /// This device only: iCloud Drive is off, or the app can't reach it.
        case device
    }

    private(set) var schemes: [TerminalScheme] = []
    private(set) var storage: Storage = .finding

    @ObservationIgnored private var cloudFolder: URL?
    @ObservationIgnored private var deviceFolder: URL?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// What each file said, by name, with the date it was read at: read again when it changes.
    @ObservationIgnored private var read: [String: (modified: Date?, profile: TerminalProfile?, problem: String?)] = [:]
    @ObservationIgnored private var reading: Set<String> = []
    @ObservationIgnored private var asked: Set<String> = []
    nonisolated private static let log = Logger(subsystem: "com.glasspowertools", category: "TerminalSchemes")

    /// Folders given here instead of iCloud's and the device's, for tests.
    init(cloudFolder: URL? = nil, deviceFolder: URL? = nil) {
        if cloudFolder != nil || deviceFolder != nil {
            self.cloudFolder = cloudFolder
            self.deviceFolder = deviceFolder
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
        Task {
            // iCloud's container must not be asked for on the main thread.
            let cloud = await Task.detached(priority: .utility) { Self.makeCloudFolder() }.value
            cloudFolder = cloud
            storage = cloud == nil ? .device : .iCloud
            #if DEBUG
            await TerminalDemoSchemes.addIfAsked(to: self)
            #endif
            refresh()
            if cloud != nil { watchCloud() }
        }
        refresh()
    }

    /// Until the library knows where its folders are, for a few seconds at most.
    func ready() async {
        for _ in 0..<50 where storage == .finding {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The folder schemes are added to: iCloud's, else this device's.
    var folder: URL? { cloudFolder ?? deviceFolder }

    func scheme(withID id: UUID) -> TerminalScheme? {
        schemes.first { $0.id == id }
    }

    /// A scheme's colors in `font`'s font: what a terminal draws with when it is chosen. Nil while
    /// it isn't on this device, or can't be read.
    func theme(forID id: UUID, font: TerminalTheme) -> TerminalTheme? {
        guard var theme = scheme(withID: id)?.theme else { return nil }
        theme.fontName = font.fontName
        theme.fontSize = font.fontSize
        return theme
    }

    // MARK: - Listing

    /// Lists the folders again, reading what is new or changed off the main thread.
    func refresh() {
        var found: [String: TerminalScheme] = [:]
        // The device's first, so iCloud's copy of a name wins.
        for folder in [deviceFolder, cloudFolder].compactMap({ $0 }) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for listed in names {
                guard let entry = TerminalSchemeFiles.entry(named: listed) else { continue }
                let file = folder.appendingPathComponent(entry.fileName)
                var downloaded = entry.isDownloaded
                if downloaded, let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    .ubiquitousItemDownloadingStatus {
                    downloaded = status == .current || status == .downloaded
                }
                found[entry.fileName] = TerminalScheme(id: TerminalSchemeFiles.id(forFileNamed: entry.fileName),
                                                       fileName: entry.fileName, file: file, isDownloaded: downloaded)
            }
        }
        var next: [TerminalScheme] = []
        for var scheme in found.values {
            if scheme.isDownloaded {
                let modified = (try? scheme.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let known = read[scheme.fileName], known.modified == modified {
                    scheme.theme = known.profile.map {
                        TerminalTheme(profile: $0, fallback: .default, id: scheme.id, withFont: false)
                            .reidentified(id: scheme.id, name: scheme.name)
                    }
                    scheme.problem = known.problem
                } else {
                    readLater(scheme, modified: modified)
                }
            } else {
                // A scheme is a few kilobytes: every one is fetched, so each is there when chosen.
                download(scheme)
            }
            next.append(scheme)
        }
        next.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if next != schemes { schemes = next }
        read = read.filter { found[$0.key] != nil }
    }

    private func readLater(_ scheme: TerminalScheme, modified: Date?) {
        guard reading.insert(scheme.fileName).inserted else { return }
        let file = scheme.file, name = scheme.fileName
        Task {
            let outcome = await Task.detached(priority: .utility) { () -> (TerminalProfile?, String?) in
                var result: (TerminalProfile?, String?) = (nil, nil)
                NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: nil) { url in
                    do { result = (try TerminalProfileReader.read(contentsOf: url), nil) } catch {
                        result = (nil, error.localizedDescription)
                    }
                }
                return result
            }.value
            reading.remove(name)
            read[name] = (modified, outcome.0, outcome.1)
            if let problem = outcome.1 { Self.log.error("Terminal scheme \(name, privacy: .public) can't be read: \(problem, privacy: .public)") }
            refresh()
        }
    }

    private func download(_ scheme: TerminalScheme) {
        guard asked.insert(scheme.fileName).inserted else { return }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: scheme.file)
        } catch {
            Self.log.error("Downloading a terminal scheme failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Adding and removing

    /// Copies Terminal profiles into the folder, each read first, and a folder's own profiles with
    /// it: one already there by the same name is replaced, so importing a set again updates it.
    /// Returns what was added, and what couldn't be, by name, in words.
    @discardableResult
    func add(_ urls: [URL]) async -> (added: [String], problems: [(name: String, problem: String)]) {
        guard let folder else {
            return ([], urls.map { ($0.lastPathComponent, "There's nowhere to keep it: turn on iCloud Drive, or check this device's storage.") })
        }
        let outcome = await Task.detached(priority: .userInitiated) { Self.copy(urls, into: folder) }.value
        for name in outcome.added { read[name] = nil }
        refresh()
        return outcome
    }

    /// Deletes a scheme's file, from every device that shares the folder. A terminal that chose it
    /// draws with your theme after.
    func remove(_ scheme: TerminalScheme) {
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: scheme.file, options: .forDeleting, error: nil) { url in
            do { try FileManager.default.removeItem(at: url) } catch { failure = error }
        }
        if let failure { Self.log.error("Deleting a terminal scheme failed: \(failure.localizedDescription, privacy: .public)") }
        read[scheme.fileName] = nil
        refresh()
    }

    /// At most this many profiles from one import: a folder of a thousand is a mistake, not a set.
    nonisolated static let maximumImport = 1000

    nonisolated private static func copy(_ urls: [URL], into folder: URL) -> (added: [String], problems: [(name: String, problem: String)]) {
        var added: [String] = []
        var problems: [(name: String, problem: String)] = []
        var files: [URL] = []
        var scoped: [URL] = []
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        for url in urls {
            if url.startAccessingSecurityScopedResource() { scoped.append(url) }
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
                // A folder's own profiles, not its folders'.
                let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                let profiles = inside.filter { TerminalSchemeFiles.entry(named: $0.lastPathComponent)?.isDownloaded == true }
                if profiles.isEmpty { problems.append((url.lastPathComponent, "There are no Terminal profiles (.terminal files) in this folder.")) }
                files += profiles
            } else {
                files.append(url)
            }
        }
        for file in files.prefix(maximumImport) {
            let name = file.lastPathComponent
            guard TerminalSchemeFiles.entry(named: name) != nil else {
                problems.append((name, TerminalThemeImportError.unsupportedFileExtension.localizedDescription))
                continue
            }
            do {
                _ = try TerminalProfileReader.read(contentsOf: file)
            } catch {
                problems.append((name, error.localizedDescription))
                continue
            }
            let destination = folder.appendingPathComponent(name)
            var failure: Error?
            var coordination: NSError?
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordination) { url in
                do {
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    try FileManager.default.copyItem(at: file, to: url)
                } catch { failure = error }
            }
            if let error = failure ?? coordination {
                log.error("Copying a terminal scheme failed: \(error.localizedDescription, privacy: .public)")
                problems.append((name, "It couldn't be copied into Terminal Themes. Check that there's space in iCloud Drive, then add it again."))
            } else {
                added.append(name)
            }
        }
        if files.count > maximumImport {
            problems.append(("\(files.count - maximumImport) more", "At most \(maximumImport) profiles come in at once. Add the rest after."))
        }
        return (added, problems)
    }

    // MARK: - Folders

    nonisolated private static func makeDeviceFolder() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent("com.glasspowertools/\(TerminalSchemeFiles.folderName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// iCloud Drive ▸ Glass Power Tools ▸ Terminal Themes: the container's Documents, which iCloud
    /// Drive shows under the app's name (`NSUbiquitousContainers` in Info.plist).
    nonisolated private static func makeCloudFolder() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let folder = container.appendingPathComponent("Documents/\(TerminalSchemeFiles.folderName)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            log.error("iCloud's Terminal Themes folder couldn't be made: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return folder
    }

    /// Files arriving from other devices, and downloads finishing, list the folder again.
    private func watchCloud() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.terminal'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        query.start()
        self.query = query
    }
}

#if DEBUG
/// Schemes for the simulator, which has no iCloud to bring the person's (`--demo-terminal-schemes`):
/// three Terminal profiles written as Terminal writes them — a dark one, a light one and a neon
/// one — then imported as Import imports a folder.
@MainActor
enum TerminalDemoSchemes {
    static func addIfAsked(to library: TerminalSchemeLibrary) async {
        guard ProcessInfo.processInfo.arguments.contains("--demo-terminal-schemes") else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Demo Terminal Themes", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let samples: [(String, [Double], [Double], [Double], [Double])] = [
            ("Demo Solarized", [0, 0.169, 0.212], [0.514, 0.58, 0.588], [0.027, 0.212, 0.259], [0.863, 0.196, 0.184]),
            ("Demo Paper", [0.98, 0.96, 0.9], [0.2, 0.2, 0.2], [0.7, 0.84, 1], [0.7, 0.1, 0.1]),
            ("Demo Neon", [0.06, 0, 0.1], [1, 0.4, 0.8], [0.3, 0.1, 0.4], [1, 0.2, 0.4]),
        ]
        for (name, background, text, selection, red) in samples {
            let profile: [String: Any] = [
                "name": name, "type": "Window Settings", "ProfileCurrentVersion": 2.04,
                "BackgroundColor": color(background), "TextColor": color(text),
                "SelectionColor": color(selection), "ANSIRedColor": color(red),
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0) {
                try? data.write(to: folder.appendingPathComponent("\(name).terminal"))
            }
        }
        await library.add([folder])
    }

    /// An `NSColor` in device RGB, archived as AppKit archives one.
    private static func color(_ rgb: [Double]) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("NSColor", for: DemoColor.self)
        archiver.encode(DemoColor(rgb), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}

@objc(GlassTerminalDemoColor)
nonisolated private final class DemoColor: NSObject, NSCoding {
    let rgb: [Double]
    init(_ rgb: [Double]) { self.rgb = rgb }
    init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        coder.encode(2, forKey: "NSColorSpace")
        let text = rgb.map { String($0) }.joined(separator: " ") + "\0"
        let bytes = Array(text.utf8)
        coder.encodeBytes(bytes, length: bytes.count, forKey: "NSRGB")
    }
}
#endif
