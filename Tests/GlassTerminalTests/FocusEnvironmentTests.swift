import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
import GlassLayers
import GlassShell
@testable import GlassTerminal

/// Focus Mode's environments (the owner, 2026-10-26: "build the upload interfaces and the
/// environment library"): which files are environments, the names added ones get, what can't be
/// added and why, and the built-ins' skies, which meet their floors and wrap without a seam.
@MainActor
@Suite("Focus Mode environments")
struct FocusEnvironmentTests {
    // MARK: - Files

    @Test("A room, a photo, iCloud's stand-in for one not here yet, and nothing else")
    func filesThatAreEnvironments() {
        #expect(FocusEnvironmentFiles.entry(named: "Loft.usdz")
            == .init(fileName: "Loft.usdz", name: "Loft", kind: .room, isDownloaded: true))
        #expect(FocusEnvironmentFiles.entry(named: "Studio.reality")?.kind == .room)
        #expect(FocusEnvironmentFiles.entry(named: "Beach.JPG")?.kind == .photo)
        #expect(FocusEnvironmentFiles.entry(named: "Alps.heic")?.kind == .photo)
        #expect(FocusEnvironmentFiles.entry(named: ".Loft.usdz.icloud")
            == .init(fileName: "Loft.usdz", name: "Loft", kind: .room, isDownloaded: false))
        #expect(FocusEnvironmentFiles.entry(named: "notes.txt") == nil)
        #expect(FocusEnvironmentFiles.entry(named: ".DS_Store") == nil)
        #expect(FocusEnvironmentFiles.entry(named: ".notes.txt.icloud") == nil)
    }

    @Test("Identifiers: a built-in's or a file's, never a path out of the folder")
    func identifiers() {
        #expect(FocusEnvironmentFiles.fileName(fromID: "file:Loft.usdz") == "Loft.usdz")
        #expect(FocusEnvironmentFiles.fileName(fromID: "file:../Loft.usdz") == nil)
        #expect(FocusEnvironmentFiles.fileName(fromID: "file:a/b.usdz") == nil)
        #expect(FocusEnvironmentFiles.fileName(fromID: "file:") == nil)
        #expect(FocusEnvironmentFiles.fileName(fromID: "file:" + String(repeating: "a", count: 400)) == nil)
        #expect(FocusEnvironmentFiles.isValidID("builtin.nightSky"))
        #expect(FocusEnvironmentFiles.isValidID(FocusEnvironment.defaultID))
        #expect(!FocusEnvironmentFiles.isValidID("builtin.moon"))
        #expect(!FocusEnvironmentFiles.isValidID("Loft.usdz"))
        #expect(FocusBuiltInEnvironment(id: "builtin.dusk") == .dusk)
    }

    @Test("An added file keeps its name unless the library has it, whatever its case")
    func addedNames() {
        #expect(FocusEnvironmentFiles.availableName(for: "Loft.usdz", taken: []) == "Loft.usdz")
        #expect(FocusEnvironmentFiles.availableName(for: "Loft.USDZ", taken: ["loft.usdz"]) == "Loft 2.usdz")
        #expect(FocusEnvironmentFiles.availableName(for: "Loft.usdz", taken: ["Loft.usdz", "Loft 2.usdz"]) == "Loft 3.usdz")
        #expect(FocusEnvironmentFiles.availableName(for: ".usdz", taken: []) == "Environment.usdz")
        #expect(FocusEnvironmentFiles.availableName(for: "a/b:c.png", taken: []) == "a-b-c.png")
    }

    @Test("A 360° photo is twice as wide as it is tall")
    func equirectangular() {
        #expect(FocusEnvironmentFiles.isEquirectangular(width: 8192, height: 4096))
        #expect(FocusEnvironmentFiles.isEquirectangular(width: 6000, height: 3000))
        #expect(FocusEnvironmentFiles.isEquirectangular(width: 4096, height: 2060))
        #expect(!FocusEnvironmentFiles.isEquirectangular(width: 4096, height: 2100))
        #expect(!FocusEnvironmentFiles.isEquirectangular(width: 3000, height: 2000))
        #expect(!FocusEnvironmentFiles.isEquirectangular(width: 0, height: 0))
    }

    // MARK: - The library

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func picture(_ name: String, width: Int, height: Int, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test("Added photos and rooms are listed after the built-ins; what isn't one says why")
    func adding() async throws {
        let library = FocusEnvironmentLibrary(cloudFolder: try folder())
        let outside = try folder()
        let pano = try picture("Pano.png", width: 400, height: 200, in: outside)
        let snapshot = try picture("Snapshot.png", width: 300, height: 200, in: outside)
        let fakeModel = outside.appendingPathComponent("Fake.usdz")
        try Data("not a model".utf8).write(to: fakeModel)
        let scene = outside.appendingPathComponent("Scene.reality")
        try Data([0, 1, 2, 3]).write(to: scene)
        let notes = outside.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notes)

        let problems = await library.add([pano, snapshot, fakeModel, scene, notes])

        #expect(problems == [.notA360Photo("Snapshot.png", width: 300, height: 200), .notAModel("Fake.usdz"),
                             .notAnEnvironment("notes.txt")])
        #expect(library.environments.map(\.id)
            == FocusBuiltInEnvironment.allCases.map(\.id) + ["file:Pano.png", "file:Scene.reality"])
        #expect(library.environment(withID: "file:Pano.png")?.kind == .photo)
        #expect(library.environment(withID: "file:Scene.reality")?.kind == .room)
        #expect(problems[0].message.contains("300 × 200"))

        // The same name again is kept beside the first.
        #expect(await library.add([pano]).isEmpty)
        #expect(library.environment(withID: "file:Pano 2.png") != nil)
    }

    @Test("Deleting one of your own takes it from the folder; a built-in stays")
    func deleting() async throws {
        let cloud = try folder()
        let library = FocusEnvironmentLibrary(cloudFolder: cloud)
        let pano = try picture("Pano.png", width: 200, height: 100, in: try folder())
        #expect(await library.add([pano]).isEmpty)
        let added = try #require(library.environment(withID: "file:Pano.png"))
        library.remove(added)
        #expect(library.environment(withID: "file:Pano.png") == nil)
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("Pano.png").path))
        library.remove(FocusEnvironment(builtIn: .dusk))
        #expect(library.environment(withID: FocusBuiltInEnvironment.dusk.id) != nil)
    }

    @Test("A room's fit is kept beside it, out of the environments' folder, read back, and gone with it; one that changes nothing is no file")
    func fitsAreKept() async throws {
        let cloud = try folder().appendingPathComponent("Environments", isDirectory: true)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let library = FocusEnvironmentLibrary(cloudFolder: cloud)
        let scene = try folder().appendingPathComponent("Loft.reality")
        try Data([0, 1, 2, 3]).write(to: scene)
        #expect(await library.add([scene]).isEmpty)
        let loft = try #require(library.environment(withID: "file:Loft.reality"))
        #expect(await library.fit(for: loft) == nil)

        let fit = FocusRoomFit(units: .metres, size: 1.25, floor: 0.1, start: FocusSpot(x: 2, y: 0, z: -1, yaw: 0.5))
        await library.save(fit, for: loft)
        let file = try #require(library.fitFile(for: loft))
        #expect(file.deletingLastPathComponent().lastPathComponent == "Environment Fits")
        #expect(!file.path.hasPrefix(cloud.path), "not among the environments, where Files would show it")
        #expect(await library.fit(for: loft) == fit)
        #expect(library.environments.count == FocusBuiltInEnvironment.allCases.count + 1, "a fit isn't an environment")

        await library.save(FocusRoomFit(), for: loft)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        await library.save(fit, for: loft)
        library.remove(loft)
        #expect(!FileManager.default.fileExists(atPath: file.path), "deleted with its room")
        #expect(library.fitFile(for: FocusEnvironment(builtIn: .dusk)) == nil)
    }

    @Test("A file iCloud hasn't brought yet is listed, to be downloaded, under its own name")
    func notYetDownloaded() throws {
        let cloud = try folder()
        try Data().write(to: cloud.appendingPathComponent(".Loft.usdz.icloud"))
        let library = FocusEnvironmentLibrary(cloudFolder: cloud)
        let loft = try #require(library.environment(withID: "file:Loft.usdz"))
        #expect(!loft.isDownloaded)
        #expect(loft.file?.lastPathComponent == "Loft.usdz")
        #expect(library.name(ofID: "file:Gone.usdz") == "Gone")
    }

    @Test("Settings sync carries the environment, and refuses a name too long to be one")
    func synced() throws {
        var preferences = ICloudPortableTerminalPreferences(
            autoReconnect: true, confirmBeforeClosing: true, saveScrollback: true,
            maximumScrollbackLines: 10_000, bellEnabled: false, visualBell: true,
            cursorStyle: "Block", blinkingCursor: true, glassFrost: "regular",
            windowOpacity: 0, blurBackground: 1, interactiveGlass: true, glassTint: "None",
            focusEnvironment: "builtin.dusk", focusOpensImmersed: true)
        try preferences.validate()
        let decoded = try JSONDecoder().decode(ICloudPortableTerminalPreferences.self,
                                               from: JSONEncoder().encode(preferences))
        #expect(decoded.focusEnvironment == "builtin.dusk")
        #expect(decoded.focusOpensImmersed == true)
        preferences.focusEnvironment = "file:" + String(repeating: "a", count: 400)
        #expect(throws: ICloudSettingsSyncError.self) { try preferences.validate() }
    }

    @Test("Only Vision Pro sends its environment and how it opens: another device's default would undo the headset's choice")
    func onlyTheHeadsetSendsItsEnvironment() {
        #if os(visionOS)
        #expect(SettingsManager.sentFromVisionPro("builtin.dusk") == "builtin.dusk")
        #expect(SettingsManager.sentFromVisionPro(true) == true)
        #else
        #expect(SettingsManager.sentFromVisionPro("builtin.dusk") == nil)
        #expect(SettingsManager.sentFromVisionPro(true) == nil)
        #endif
    }

    @Test("Open Immersed is off, as Focus Mode always opened, and is kept on this device")
    func opensImmersedIsKept() throws {
        let suite = "FocusOpensImmersed.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func settings(loaded: Bool) -> SettingsManager {
            SettingsManager(loadImmediately: loaded, settingsDefaults: defaults, sshKeyDefaults: defaults,
                            iCloudSettingsSyncService: ICloudSettingsSyncService(store: InMemorySettingsStore(), writerID: UUID()),
                            workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: InMemorySettingsStore()),
                            layers: GlassLayerStore.forTest())
        }
        let first = settings(loaded: true)
        #expect(!first.focusOpensImmersed)
        first.focusOpensImmersed = true
        first.saveSettings()
        #expect(settings(loaded: true).focusOpensImmersed)
    }

    @Test("A room goes around the person, floor at their feet; anything smaller stands on the floor ahead")
    func placement() {
        // A 6 m room whose floor is 0.2 m below its origin, off to one side.
        let room = FocusRoomPlacement.offset(min: [1, -0.2, -3], max: [7, 2.8, 3])
        #expect(room == [-4, 0.2, 0])
        // A half-metre object: its near side 1.5 m ahead, standing on the floor.
        let object = FocusRoomPlacement.offset(min: [-0.25, 0.1, -0.1], max: [0.25, 0.6, 0.1])
        #expect(object.x == 0 && object.y == -0.1)
        #expect(abs((object.z + 0.1) - -1.5) < 0.0001)
        #expect(FocusRoomPlacement.offset(min: [0, 0, 0], max: [.infinity, 1, 1]) == .zero)
        // One that isn't a room says so, with its size; a room says nothing.
        #expect(FocusRoomPlacement.objectNote(name: "iMac", min: [-0.25, 0, -0.1], max: [0.25, 0.5, 0.1])?
            .hasPrefix("“iMac” is 50 cm across, smaller than a room") == true)
        #expect(FocusRoomPlacement.objectNote(name: "Loft", min: [1, -0.2, -3], max: [7, 2.8, 3]) == nil)
    }

    // MARK: - The built-ins' pictures

    private func color(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> FocusEnvironmentArt.Color {
        let index = (y * width + x) * 4
        return .init(Double(pixels[index]) / 255, Double(pixels[index + 1]) / 255, Double(pixels[index + 2]) / 255)
    }

    @Test("Each sky is the same every time, and wraps around without a seam",
          arguments: [FocusBuiltInEnvironment.nightSky, .dusk, .grid, .studio])
    func skies(_ environment: FocusBuiltInEnvironment) {
        let width = 512, height = 256
        let pixels = FocusEnvironmentArt.skyPixels(environment, width: width)
        #expect(pixels == FocusEnvironmentArt.skyPixels(environment, width: width))
        // Where the picture's ends meet, behind the person, its columns are alike.
        var seam = 0.0, across = 0.0
        for y in 0..<height {
            let left = color(pixels, width: width, x: 0, y: y), right = color(pixels, width: width, x: width - 1, y: y)
            let middle = color(pixels, width: width, x: width / 2, y: y), next = color(pixels, width: width, x: width / 2 + 1, y: y)
            seam += abs(left.r - right.r) + abs(left.g - right.g) + abs(left.b - right.b)
            across += abs(middle.r - next.r) + abs(middle.g - next.g) + abs(middle.b - next.b)
        }
        #expect(seam / Double(height) < 0.02, "the seam differs by \(seam / Double(height)) a row")
        #expect(seam <= across * 3 + 0.5)
    }

    @Test("Each floor's edge is its sky's ground, so they meet without a line",
          arguments: [FocusBuiltInEnvironment.nightSky, .dusk, .grid, .studio])
    func floorsMeetTheirSkies(_ environment: FocusBuiltInEnvironment) {
        let width = 512
        let pixels = FocusEnvironmentArt.skyPixels(environment, width: width)
        // Just below the horizon, ahead.
        let below = color(pixels, width: width, x: width / 2, y: width / 4 + 1)
        let ground = FocusEnvironmentArt.groundColor(environment)
        #expect(abs(below.r - ground.r) <= 2.0 / 255 && abs(below.g - ground.g) <= 2.0 / 255 && abs(below.b - ground.b) <= 2.0 / 255)
        let edge = FocusEnvironmentArt.floorColor(environment, distance: Double(FocusEnvironmentArt.gridHalfWidth))
        #expect(edge == ground)
        #expect(FocusEnvironmentArt.floorColor(environment, distance: 0) == FocusEnvironmentArt.floorCenterColor(environment))
    }

    @Test("Dusk's sun set ahead of the person: the picture's middle")
    func duskFacesTheSunset() {
        let width = 512
        let pixels = FocusEnvironmentArt.skyPixels(.dusk, width: width)
        // A row above the mountains, brightest where the sun went down.
        let row = Int((90 - 11.0) / 180 * Double(width / 2))
        let brightest = (0..<width).max { a, b in
            let ca = color(pixels, width: width, x: a, y: row), cb = color(pixels, width: width, x: b, y: row)
            return ca.r + ca.g + ca.b < cb.r + cb.g + cb.b
        }
        #expect(abs((brightest ?? 0) - width / 2) < width / 20)
    }

    @Test("Grid's cell has its lines along its edges and floor between them")
    func gridTile() throws {
        let tile = try #require(FocusEnvironmentArt.gridTile(size: 64))
        let data = try #require(tile.dataProvider?.data as Data?)
        let edge = data[(32 * 64 + 0) * 4 + 1], middle = data[(32 * 64 + 32) * 4 + 1]
        #expect(edge > 100)
        #expect(middle < 20)
    }

    @Test("Every built-in has a preview")
    func previews() {
        for environment in FocusBuiltInEnvironment.allCases {
            let preview = FocusEnvironmentArt.preview(environment, width: 120)
            #expect(preview?.width == 120 && preview?.height == 60)
        }
    }
}
