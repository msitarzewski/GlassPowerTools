import Foundation
import GlassSSHTransport
import GlassTerminalEmulator
import ImageIO
import NIOCore
import Testing
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
@testable import GlassTerminal

/// Files dropped on an SSH terminal go up to the host and the host's paths are typed (W14,
/// 2026-10-09). Everything here runs against an in-memory host behind the real `SFTPClient`; no
/// SSH. The upload itself is a stand-in that writes through that client: the browser's verified
/// uploader keeps its resume records in Application Support, which an unsandboxed Mac app shares
/// with the tests.
@Suite("Files dropped on an SSH terminal")
@MainActor
struct TerminalRemoteDropTests {
    private static let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-09, mid-morning.
    private static let today = Date(timeIntervalSince1970: 1_791_540_000)
    private static let home = "/home/alpha"
    private static let day = "/home/alpha/.cache/glass-power-tools/dropped/2026-10-09"

    // MARK: The plan

    @Test("names made unique, the date folder, escaping, and the text typed — never a failed file's")
    func plan() {
        #expect(TerminalRemoteDropPlan.dayName(for: Self.today, timeZone: Self.utc) == "2026-10-09")
        #expect(TerminalRemoteDropPlan.dayName(for: Date(timeIntervalSince1970: 1_791_590_400 - 60),
                                               timeZone: TimeZone(secondsFromGMT: 3_600)!) == "2026-10-10",
                "the device's own calendar day")
        #expect(TerminalRemoteDropPlan.root(home: Self.home) == "/home/alpha/.cache/glass-power-tools/dropped")
        #expect(TerminalRemoteDropPlan.root(home: "/") == "/.cache/glass-power-tools/dropped")

        var taken = Set(["photo.jpg", "Notes.TXT"].map(TerminalRemoteDropPlan.collisionKey))
        #expect(TerminalRemoteDropPlan.uniqueName("photo.jpg", taken: &taken) == "photo-2.jpg")
        #expect(TerminalRemoteDropPlan.uniqueName("photo.jpg", taken: &taken) == "photo-3.jpg")
        #expect(TerminalRemoteDropPlan.uniqueName("notes.txt", taken: &taken) == "notes-2.txt", "case is ignored")
        #expect(TerminalRemoteDropPlan.uniqueName("README", taken: &taken) == "README")
        #expect(TerminalRemoteDropPlan.uniqueName("README", taken: &taken) == "README-2")
        #expect(TerminalRemoteDropPlan.remoteName(for: "a/b\u{7}.png") == "a_b_.png")
        #expect(TerminalRemoteDropPlan.remoteName(for: "  ") == "dropped-file")
        #expect(TerminalRemoteDropPlan.remoteName(for: "..") == "dropped-file")

        let outcomes: [TerminalRemoteDropOutcome] = [
            .arrived("my photo.jpg", at: Self.day + "/my photo.jpg"),
            .failed("broken.png", .didNotFinish),
            .arrived("it's.txt", at: Self.day + "/it's.txt"),
        ]
        let typed = TerminalRemoteDropPlan.typedText(for: outcomes)
        #expect(typed == Self.day + #"/my\ photo.jpg "# + Self.day + #"/it\'s.txt "#,
                "escaped, space-separated, a trailing space")
        #expect(typed?.contains("broken") == false, "a file that didn't arrive types nothing")
        #expect(TerminalRemoteDropPlan.typedText(for: [.failed("broken.png", .connectionLost)]) == nil)
        #expect(TerminalRemoteDropPlan.failureMessage(for: outcomes)
                == "Couldn't upload broken.png: the upload didn't finish. Try again.")
        #expect(TerminalRemoteDropPlan.failureMessage(for: [.failed("photo.heic", .folderRefused)])
                == "Couldn't upload photo.heic: the host refused the folder. Check that your account can write to ~/.cache.")
        #expect(TerminalRemoteDropPlan.progressText(index: 1, of: 3, name: "b.png") == "Uploading 2 of 3 files…")
        #expect(TerminalRemoteDropPlan.progressText(index: 0, of: 1, name: "b.png") == "Uploading b.png…")
    }

    // MARK: HEIC to JPEG

    nonisolated private static var heicEncodable: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(UTType.heic.identifier) == true
    }

    @Test("a HEIC photo goes as an upright JPEG; a PNG goes as it is", .enabled(if: heicEncodable))
    func heicToJPEG() async throws {
        let folder = try Self.temporaryFolder("drop-heic")
        defer { try? FileManager.default.removeItem(at: folder) }
        // 40 wide and 20 high, with an orientation that says "turn it a quarter right".
        let heic = folder.appendingPathComponent("IMG_0001.heic")
        try Self.writeImage(to: heic, type: .heic, width: 40, height: 20, orientation: 6)
        let png = folder.appendingPathComponent("shot.png")
        try Self.writeImage(to: png, type: .png, width: 8, height: 8, orientation: 1)

        let converted = try await TerminalDropImageConversion.uploadable(heic, writingInto: folder)
        #expect(converted.lastPathComponent == "IMG_0001.jpg")
        let source = try #require(CGImageSourceCreateWithURL(converted as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 20, "turned upright")
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 40)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)

        #expect(try await TerminalDropImageConversion.uploadable(png, writingInto: folder) == png)
    }

    // MARK: Uploading

    @Test("the folders are made, the bytes arrive, and the paths are typed in order")
    func uploadsThroughSFTP() async throws {
        let host = DropTestHost(home: Self.home)
        let folder = try Self.temporaryFolder("drop-upload")
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try Self.file("photo.jpg", in: folder.appendingPathComponent("a"), contents: "one")
        let second = try Self.file("photo.jpg", in: folder.appendingPathComponent("b"), contents: "two")
        let third = try Self.file("notes v2.txt", in: folder, contents: "three")
        let session = Self.connectedSession()
        let drops = Self.drops(on: host)
        var typed: [String] = []

        #expect(drops.receive(files: [first, second, third], on: session) { typed.append($0) })
        await drops.waitForDrop(on: session.id)

        for path in ["/home/alpha/.cache", "/home/alpha/.cache/glass-power-tools",
                     "/home/alpha/.cache/glass-power-tools/dropped", Self.day] {
            #expect(await host.permissions(of: path) == 0o700, "\(path): made, for this account alone")
        }
        #expect(await host.data(at: Self.day + "/photo.jpg") == Data("one".utf8))
        #expect(await host.data(at: Self.day + "/photo-2.jpg") == Data("two".utf8), "unique, never replaced")
        #expect(await host.data(at: Self.day + "/notes v2.txt") == Data("three".utf8))
        #expect(typed == [Self.day + "/photo.jpg " + Self.day + "/photo-2.jpg " + Self.day + #"/notes\ v2.txt "#])
        #expect(drops.statuses[session.id] == nil, "nothing to say when every file arrived")
    }

    @Test("a file that didn't arrive types nothing, and the terminal says why")
    func failedFileTypesNothing() async throws {
        let host = DropTestHost(home: Self.home)
        let folder = try Self.temporaryFolder("drop-failure")
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = try Self.file("good.txt", in: folder, contents: "fine")
        let broken = try Self.file("broken.bin", in: folder, contents: "never")
        let session = Self.connectedSession()
        let drops = Self.drops(on: host)
        var typed: [String] = []

        #expect(drops.receive(files: [broken, good], on: session) { typed.append($0) })
        await drops.waitForDrop(on: session.id)

        #expect(typed == [Self.day + "/good.txt "])
        #expect(await host.data(at: Self.day + "/broken.bin") == nil)
        #expect(drops.statuses[session.id] == TerminalRemoteDropStatus(
            kind: .problem, text: "Couldn't upload broken.bin: the upload didn't finish. Try again."))

        // A folder the host refuses: nothing goes, nothing is typed.
        let refusing = DropTestHost(home: Self.home, refusing: ["/home/alpha/.cache"])
        let refusingDrops = Self.drops(on: refusing)
        var refusedTyping: [String] = []
        #expect(refusingDrops.receive(files: [good], on: session) { refusedTyping.append($0) })
        await refusingDrops.waitForDrop(on: session.id)
        #expect(refusedTyping.isEmpty)
        #expect(refusingDrops.statuses[session.id]?.text
                == "Couldn't upload good.txt: the host refused the folder. Check that your account can write to ~/.cache.")
    }

    @Test("a HEIC that can't be converted goes as it is, and the terminal says so")
    func unconvertibleHEIC() async throws {
        let host = DropTestHost(home: Self.home)
        let folder = try Self.temporaryFolder("drop-bad-heic")
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try Self.file("photo.heic", in: folder, contents: "not an image")
        let session = Self.connectedSession()
        let drops = Self.drops(on: host)
        var typed: [String] = []

        #expect(drops.receive(files: [photo], on: session) { typed.append($0) })
        await drops.waitForDrop(on: session.id)

        #expect(typed == [Self.day + "/photo.heic "])
        #expect(await host.data(at: Self.day + "/photo.heic") == Data("not an image".utf8))
        #expect(drops.statuses[session.id] == TerminalRemoteDropStatus(
            kind: .problem, text: "photo.heic went as HEIC: it couldn't be converted to JPEG."))
    }

    @Test("a terminal that isn't connected refuses the drop, and says so")
    func disconnectedRefuses() async throws {
        let folder = try Self.temporaryFolder("drop-disconnected")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try Self.file("photo.jpg", in: folder, contents: "x")
        let session = TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"))
        var opened = false
        let drops = TerminalRemoteDrops(openClient: { _ in
            opened = true
            throw SSHError.notConnected
        }, upload: Self.writeThroughClient)
        var typed: [String] = []

        #expect(!drops.receive(files: [file], on: session) { typed.append($0) })
        await drops.waitForDrop(on: session.id)

        #expect(drops.statuses[session.id] == TerminalRemoteDropStatus(
            kind: .notice, text: "Not connected. Reconnect, then try again."))
        #expect(!opened, "nothing was sent")
        #expect(typed.isEmpty)
    }

    // MARK: Pasted

    @Test("a paste is a file when it holds a picture, or a file with no text; else it is text")
    func pastedKinds() {
        let file = SFTPIncomingDrop.isPastedFile
        #expect(file(["public.png"]))
        #expect(file(["public.utf8-plain-text", "public.jpeg"]), "a picture, whatever else it carries")
        #expect(file(["com.adobe.pdf"]))
        #expect(file(["public.file-url", "com.adobe.pdf"]), "read for its content")
        #expect(!file(["public.utf8-plain-text"]))
        #expect(!file(["public.rtf", "public.utf8-plain-text"]))
        #expect(!file(["public.url", "public.utf8-plain-text"]), "a link is text")
        #expect(!file(["public.url"]))
        #expect(!file(["public.file-url"]), "a name the app may not open, with nothing to read")
        #expect(!file(["com.example.never-declared"]))
        #expect(!file([]))
        #expect(SFTPIncomingDrop.fileType(in: ["public.utf8-plain-text", "public.png"]) == "public.png", "the picture")
        #expect(SFTPIncomingDrop.fileType(in: ["com.adobe.pdf", "public.utf8-plain-text"]) == "com.adobe.pdf")
    }

    @Test("a picture pasted goes up as Pasted.png and its path is typed; text pasted is left to be typed")
    func pastedPictureUploads() async throws {
        let host = DropTestHost(home: Self.home)
        let session = Self.connectedSession()
        let drops = Self.drops(on: host)
        var typed: [String] = []
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
        // As the clipboard has a picture: some text about it first, then the picture.
        let picture = NSItemProvider()
        picture.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { done in
            done(Data("a caption".utf8), nil); return nil
        }
        picture.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { done in
            done(png, nil); return nil
        }
        let caption = NSItemProvider(object: "a caption" as NSString)

        #expect(drops.receive(pasted: [picture, caption], on: session) { typed.append($0) })
        await drops.waitForDrop(on: session.id)

        #expect(await host.data(at: Self.day + "/Pasted.png") == png, "the picture, not its caption")
        #expect(typed == [Self.day + "/Pasted.png "])

        #expect(!drops.receive(pasted: [caption], on: session) { typed.append($0) }, "text is typed as text")
        #expect(!drops.receive(pasted: [], on: session) { typed.append($0) })
        #expect(typed.count == 1)
        #expect(drops.statuses[session.id] == nil)

        let offline = TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"))
        #expect(drops.receive(pasted: [picture], on: offline) { typed.append($0) }, "a picture is never typed as text")
        #expect(drops.statuses[offline.id] == TerminalRemoteDropStatus(
            kind: .notice, text: "Not connected. Reconnect, then try again."))
        #expect(typed.count == 1)
    }

    // MARK: Insert Path

    @Test("Insert Path types a selection's escaped paths into the browser's own terminal")
    func insertPath() {
        let alpha = TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"))
        let bravo = TerminalSession(server: ServerConfiguration(name: "bravo", host: "192.0.2.11", username: "ann"))
        let library = TerminalSession(server: ServerConfiguration(name: "bravo", host: "192.0.2.11", username: "ann"),
                                      purpose: .sftp)
        let sessions = [alpha, bravo, library]
        let lookup: (UUID) -> TerminalSession? = { id in sessions.first { $0.id == id } }
        var typed: [(UUID, String)] = []

        let terminal = TerminalRemoteDrops.terminal(forBrowserSession: bravo.id, in: lookup)
        #expect(terminal === bravo)
        #expect(TerminalRemoteDrops.insertPaths(["/srv/www/my site", "/srv/www/it's.md"], into: terminal) {
            typed.append(($0.id, $1))
        })
        #expect(typed.map { $0.0 } == [bravo.id], "the browser's own terminal, and no other")
        #expect(typed.first?.1 == #"/srv/www/my\ site /srv/www/it\'s.md "#)

        // A browser opened from the library has no terminal: Insert Path isn't offered, and types nothing.
        #expect(TerminalRemoteDrops.terminal(forBrowserSession: library.id, in: lookup) == nil)
        #expect(!TerminalRemoteDrops.insertPaths(["/srv/www/a"], into: library) { typed.append(($0.id, $1)) })
        #expect(typed.count == 1)
    }

    // MARK: The Mac's SSH panes

    #if os(macOS)
    @Test("a drop on a Mac's SSH pane is uploaded and types the host's path, not the Mac's")
    func macSSHPaneUploads() async throws {
        let model = SwiftTermHostModel()
        guard case .localPaths(let local) = TerminalDropRoute.resolve(localModel: model, session: nil) else {
            Issue.record("a local pane types this Mac's paths")
            return
        }
        #expect(local === model)
        let session = Self.connectedSession()
        guard case .upload(let target) = TerminalDropRoute.resolve(localModel: nil, session: session) else {
            Issue.record("an SSH pane uploads")
            return
        }
        #expect(target === session)

        let folder = try Self.temporaryFolder("drop-mac")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try Self.file("diagram.png", in: folder, contents: "png")
        // A private pasteboard: nothing of the real drag pasteboard can stand in for this drop.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("drop-test-\(UUID())"))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        defer { pasteboard.releaseGlobally() }
        let drop = try #require(SFTPIncomingDrop(providers: [], pasteboard: pasteboard))
        let host = DropTestHost(home: Self.home)
        let drops = Self.drops(on: host)
        var typed: [String] = []

        #expect(drops.receive(drop, on: target) { typed.append($0) })
        await drops.waitForDrop(on: session.id)

        #expect(typed == [Self.day + "/diagram.png "])
        #expect(!typed.joined().contains(folder.path), "not this Mac's path")
        #expect(await host.data(at: Self.day + "/diagram.png") == Data("png".utf8))
    }
    #endif

    // MARK: The week-old clean-up

    @Test("week-old drops are cleared once per connection, and nothing outside the drop folder")
    func clearsOnlyWeekOldDrops() async throws {
        let root = "/home/alpha/.cache/glass-power-tools/dropped"
        let host = DropTestHost(home: Self.home)
        await host.makeFolders([
            root + "/2026-10-01/nested", root + "/2026-10-02", root + "/notes",
            "/home/alpha/project/2026-01-01", "/home/alpha/.cache/other/2026-01-01",
        ])
        await host.put(root + "/2026-10-01/old.png", "old")
        await host.put(root + "/2026-10-01/nested/older.txt", "old")
        await host.put(root + "/2026-10-02/recent.png", "a week ago, to the day")
        await host.put(root + "/notes/2020-01-01.txt", "not a day folder")
        await host.put(root + "/2026-09-02", "a file named like a day")
        await host.link(root + "/2026-09-01", to: "/home/alpha/project")
        await host.put("/home/alpha/project/2026-01-01/keep.txt", "outside")
        await host.put("/home/alpha/.cache/other/2026-01-01/keep.txt", "outside")

        let folder = try Self.temporaryFolder("drop-clean")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try Self.file("new.txt", in: folder, contents: "new")
        let session = Self.connectedSession()
        let drops = Self.drops(on: host)

        #expect(drops.receive(files: [file], on: session) { _ in })
        await drops.waitForDrop(on: session.id)

        #expect(await !host.exists(root + "/2026-10-01"), "more than a week old: cleared, contents and all")
        for kept in [root + "/2026-10-02/recent.png", root + "/notes/2020-01-01.txt", root + "/2026-09-02",
                     root + "/2026-09-01", "/home/alpha/project/2026-01-01/keep.txt",
                     "/home/alpha/.cache/other/2026-01-01/keep.txt", Self.day + "/new.txt"] {
            #expect(await host.exists(kept), "\(kept) stays")
        }

        // Once per connection: the next drop on it doesn't clear again.
        await host.makeFolders([root + "/2026-09-15"])
        #expect(drops.receive(files: [file], on: session) { _ in })
        await drops.waitForDrop(on: session.id)
        #expect(await host.exists(root + "/2026-09-15"))

        // A new connection clears again.
        session.state = .disconnected
        for _ in 0..<200 where drops.clearedConnections.contains(session.id) {
            try await Task.sleep(for: .milliseconds(5))
        }
        session.state = .connected
        #expect(drops.receive(files: [file], on: session) { _ in })
        await drops.waitForDrop(on: session.id)
        #expect(await !host.exists(root + "/2026-09-15"))
    }

    // MARK: Helpers

    /// Writes the bytes through the SFTP client, refusing to replace a file, as the verified
    /// upload does; a file named `broken…` never arrives.
    private static let writeThroughClient: TerminalRemoteDropHost.Upload = { client, file, _, directory, name, _ in
        guard !name.hasPrefix("broken") else { throw TerminalRemoteDropFailure.didNotFinish }
        let data = try Data(contentsOf: file)
        let remote = try await client.openFile(
            filePath: SFTPBrowserView.remotePath(directory: directory, basename: name),
            flags: [.write, .create, .forceCreate]
        )
        try await remote.write(ByteBuffer(bytes: data))
        try await remote.close()
    }

    private static func drops(on host: DropTestHost) -> TerminalRemoteDrops {
        let drops = TerminalRemoteDrops(
            openClient: { _ in SFTPClient(session: host, extensions: SFTPServerExtensions([SFTPServerExtensions.hardLink: "1"])) },
            upload: writeThroughClient
        )
        drops.now = { today }
        drops.timeZone = utc
        return drops
    }

    private static func connectedSession() -> TerminalSession {
        let session = TerminalSession(server: ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann"))
        session.state = .connected
        return session
    }

    private static func temporaryFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func file(_ name: String, in folder: URL, contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private static func writeImage(to url: URL, type: UTType, width: Int, height: Int, orientation: Int) throws {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// An in-memory host: folders, files and links, read through `SFTPSession` as a server reads them —
/// a listing reports a link as a link, as OpenSSH's does.
actor DropTestHost: SFTPSession {
    nonisolated private enum Node {
        case folder(permissions: UInt32)
        case file(Data)
        case link(String)
    }

    nonisolated private struct Refused: Error {}

    private let home: String
    private let refusing: Set<String>
    private var nodes: [String: Node] = [:]

    init(home: String, refusing: Set<String> = []) {
        self.home = home
        self.refusing = refusing
        var path = ""
        nodes["/"] = .folder(permissions: 0o755)
        for component in home.split(separator: "/") {
            path += "/" + component
            nodes[path] = .folder(permissions: 0o755)
        }
    }

    // Seeding and reading back.

    func makeFolders(_ paths: [String]) {
        for path in paths {
            var current = ""
            for component in path.split(separator: "/") {
                current += "/" + component
                if nodes[current] == nil { nodes[current] = .folder(permissions: 0o755) }
            }
        }
    }

    func put(_ path: String, _ contents: String) { nodes[path] = .file(Data(contents.utf8)) }
    func link(_ path: String, to target: String) { nodes[path] = .link(target) }
    func exists(_ path: String) -> Bool { nodes[path] != nil }

    func data(at path: String) -> Data? {
        if case .file(let data) = nodes[path] { return data }
        return nil
    }

    func permissions(of path: String) -> UInt32? {
        if case .folder(let permissions) = nodes[path] { return permissions }
        return nil
    }

    // SFTPSession

    func list(_ path: String) async throws -> [SFTPEntry] {
        guard case .folder = nodes[path] else { throw Refused() }
        let prefix = path == "/" ? "/" : path + "/"
        return nodes.keys
            .filter { $0.hasPrefix(prefix) && $0 != path && !$0.dropFirst(prefix.count).contains("/") }
            .sorted()
            .map { SFTPEntry(name: String($0.dropFirst(prefix.count)), path: $0, attributes: attributes(of: nodes[$0]!)) }
    }

    func attributes(at path: String, followSymlinks: Bool) async throws -> SFTPAttributes {
        guard var node = nodes[path] else { throw Refused() }
        if followSymlinks, case .link(let target) = node {
            guard let resolved = nodes[target] else { throw Refused() }
            node = resolved
        }
        return attributes(of: node)
    }

    private func attributes(of node: Node) -> SFTPAttributes {
        switch node {
        case .folder(let permissions): SFTPAttributes(size: 0, permissions: 0o040000 | permissions)
        case .file(let data): SFTPAttributes(size: UInt64(data.count), permissions: 0o100644)
        case .link: SFTPAttributes(size: 0, permissions: 0o120777)
        }
    }

    func realPath(_ path: String) async throws -> String { path == "." ? home : path }

    func open(_ path: String, mode: SFTPOpenMode, permissions: UInt32?) async throws -> any SFTPFileHandle {
        if mode.contains(.create) {
            if mode.contains(.exclusive), nodes[path] != nil { throw Refused() }
            let parent = (path as NSString).deletingLastPathComponent
            guard case .folder = nodes[parent] else { throw Refused() }
            if nodes[path] == nil { nodes[path] = .file(Data()) }
        }
        guard case .file = nodes[path] else { throw Refused() }
        return Handle(host: self, path: path)
    }

    func createDirectory(_ path: String) async throws {
        let parent = (path as NSString).deletingLastPathComponent
        guard !refusing.contains(path), nodes[path] == nil, case .folder = nodes[parent] else { throw Refused() }
        nodes[path] = .folder(permissions: 0o755)
    }

    func removeFile(_ path: String) async throws {
        guard let node = nodes[path] else { throw Refused() }
        if case .folder = node { throw Refused() }
        nodes[path] = nil
    }

    func removeDirectory(_ path: String) async throws {
        guard case .folder = nodes[path], nodes.keys.allSatisfy({ !$0.hasPrefix(path + "/") }) else { throw Refused() }
        nodes[path] = nil
    }

    func rename(_ path: String, to newPath: String) async throws { throw Refused() }
    func posixRename(_ path: String, to newPath: String) async throws { throw Refused() }
    func hardLink(_ path: String, to newPath: String) async throws { throw Refused() }

    func setAttributes(_ changes: SFTPAttributeChanges, at path: String) async throws {
        guard let node = nodes[path] else { throw Refused() }
        if case .folder = node, let permissions = changes.permissions { nodes[path] = .folder(permissions: permissions) }
    }

    var serverExtensions: SFTPServerExtensions { SFTPServerExtensions([SFTPServerExtensions.hardLink: "1"]) }
    var isActive: Bool { true }
    func close() async throws {}

    fileprivate func write(_ data: Data, to path: String, at offset: UInt64) throws {
        guard case .file(var existing) = nodes[path] else { throw Refused() }
        let start = Int(offset)
        if existing.count < start { existing.append(Data(count: start - existing.count)) }
        existing.replaceSubrange(start..<min(existing.count, start + data.count), with: data)
        nodes[path] = .file(existing)
    }

    fileprivate func read(_ path: String, from offset: UInt64, length: UInt32) throws -> Data {
        guard case .file(let data) = nodes[path] else { throw Refused() }
        guard Int(offset) < data.count else { return Data() }
        return data.subdata(in: Int(offset)..<min(data.count, Int(offset) + Int(length)))
    }

    nonisolated private struct Handle: SFTPFileHandle {
        let host: DropTestHost
        let path: String
        func read(from offset: UInt64, length: UInt32) async throws -> Data { try await host.read(path, from: offset, length: length) }
        func write(_ data: Data, at offset: UInt64) async throws { try await host.write(data, to: path, at: offset) }
        func attributes() async throws -> SFTPAttributes { try await host.attributes(at: path, followSymlinks: true) }
        func synchronize() async throws {}
        func close() async throws {}
    }
}
