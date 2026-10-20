import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import GlassLayers
@testable import GlassTerminal
@testable import GlassTerminalEmulator

/// A terminal window's look (D84): what it shows behind its text, the text's palette and glow,
/// and the readability guard over all of it.
@MainActor
@Suite("Terminal looks")
struct TerminalLooksTests {
    // MARK: - Settings

    @Test("a window that sets nothing looks as it always has")
    func defaults() {
        let style = TerminalLookStyle.resolved(GlassWindowOverrides())
        #expect(style.backdrop == .none)
        #expect(!style.drawsBackdrop)
        #expect(style.glow == 0)
        #expect(style.phosphor == .none)
        let theme = TerminalTheme.default
        #expect(TerminalWindowProfile.theme(GlassWindowOverrides(), over: theme, library: .initial(theme: theme, at: .distantPast))
                == theme, "the theme untouched")
    }

    @Test("Start From sets the whole look and keeps the window's other settings and its picture")
    func presets() throws {
        var window = GlassWindowOverrides()
        window[TerminalWindowSettings.fontSize] = 18
        window[TerminalWindowSettings.glowColor] = .cyan
        let picture = UUID().uuidString + ".jpg"
        window[TerminalWindowSettings.backdropPicture] = picture

        let rain = TerminalLookStyle.resolved(TerminalLookPreset.digitalRain.applied(to: window))
        #expect(rain.backdrop == .rain && rain.phosphor == .matrix && rain.glow > 0)
        #expect(rain.glowColor == .text, "a look replaces the glow colour the window had")

        let cleared = TerminalLookPreset.clear.applied(to: TerminalLookPreset.synthwave.applied(to: window))
        #expect(cleared[TerminalWindowSettings.fontSize] == 18, "not part of the look")
        #expect(cleared[TerminalWindowSettings.backdropPicture] == picture, "the picture stays chosen")
        #expect(!TerminalLookStyle.resolved(cleared).drawsBackdrop)
        #expect(TerminalLookStyle.resolved(cleared).glow == 0)
    }

    @Test("a picture is a name this store gives, never a path")
    func pictureNames() {
        let name = UUID().uuidString + ".jpg"
        #expect(TerminalBackgroundPictures.isName(name))
        for bad in ["../../etc/passwd", "/Users/someone/photo.jpg", "photo.jpg", name + "/..", UUID().uuidString + ".png"] {
            #expect(!TerminalBackgroundPictures.isName(bad), "\(bad)")
            #expect(TerminalBackgroundPictures.url(for: bad) == nil)
            var window = GlassWindowOverrides()
            window[TerminalWindowSettings.backdropPicture] = bad
            #expect(window[TerminalWindowSettings.backdropPicture] == nil, "refused as a window's setting too")
        }
    }

    // MARK: - Pictures

    private func png(width: Int, height: Int, gray: CGFloat) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("a chosen picture is kept scaled to fit, and read back by its name")
    func importing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("looks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = try TerminalBackgroundPictures.importPicture(try png(width: 4_000, height: 1_000, gray: 1), into: directory)
        #expect(TerminalBackgroundPictures.isName(name))
        let image = try #require(TerminalBackgroundPictures.image(named: name, in: directory))
        #expect(max(image.width, image.height) == TerminalBackgroundPictures.maximumPixelSize)
        #expect(image.width / image.height == 4, "its shape kept")
        #expect(TerminalBackgroundPictures.brightness(of: image) > 0.95)
        #expect(TerminalBackgroundPictures.image(named: UUID().uuidString + ".jpg", in: directory) == nil,
                "a name this device doesn't have")
    }

    @Test("what isn't a picture, or is too large to be one, is refused")
    func refusing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("looks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: TerminalBackgroundPictures.ImportError.notAPicture) {
            try TerminalBackgroundPictures.importPicture(Data("not a picture".utf8), into: directory)
        }
        #expect(throws: TerminalBackgroundPictures.ImportError.tooLarge) {
            try TerminalBackgroundPictures.importPicture(Data(count: TerminalBackgroundPictures.maximumInputBytes + 1),
                                                         into: directory)
        }
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(kept.isEmpty, "nothing kept")
    }

    @Test("a dark picture reads as dark")
    func brightness() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("looks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = try TerminalBackgroundPictures.importPicture(try png(width: 64, height: 64, gray: 0.05), into: directory)
        let image = try #require(TerminalBackgroundPictures.image(named: name, in: directory))
        #expect(TerminalBackgroundPictures.brightness(of: image) < 0.02)
    }

    // MARK: - Palettes

    @Test("a monochrome phosphor colours the text by filter and leaves the theme; Vaporwave is a palette")
    func phosphor() {
        let theme = TerminalTheme.default
        for phosphor in [TerminalPhosphor.green, .amber, .matrix] {
            #expect(phosphor.isMonochrome)
            #expect(phosphor.applied(to: theme) == theme, "\(phosphor): every colour, 24-bit too, by the filter")
            #expect(phosphor.textColor(theme: theme) == phosphor.primary)
        }
        #expect(!TerminalPhosphor.vaporwave.isMonochrome)
        let neon = TerminalPhosphor.vaporwave.applied(to: theme)
        #expect(neon.ansiColors == TerminalPhosphor.vaporwaveANSI)
        #expect(neon.foreground == TerminalPhosphor.vaporwave.primary)
        #expect(neon.background == theme.background, "the glass behind the text kept")
        #expect(TerminalPhosphor.none.applied(to: theme) == theme)
        #expect(TerminalPhosphor.none.textColor(theme: theme) == theme.foreground)
    }

    @Test("a window's palette reaches the theme its terminals draw with")
    func paletteInProfile() {
        var window = GlassWindowOverrides()
        window[TerminalWindowSettings.phosphor] = .vaporwave
        let theme = TerminalTheme.default
        let drawn = TerminalWindowProfile.theme(window, over: theme, library: .initial(theme: theme, at: .distantPast))
        #expect(drawn.foreground == TerminalPhosphor.vaporwave.primary)
        #expect(TerminalLookStyle.resolved(window).phosphor == .vaporwave)
    }

    // MARK: - Readability

    @Test("the scrim is the window's own unless the text would fall below 4.5:1, then just enough")
    func readability() {
        let white = 1.0, black = 0.0
        // Light text over a dark backdrop: the window's own scrim.
        #expect(TerminalReadability.scrimOpacity(background: 0.02, text: white, scrim: black, minimum: 0.35) == 0.35)
        // Light text over a bright picture: raised until it reads.
        let raised = TerminalReadability.scrimOpacity(background: 0.9, text: white, scrim: black, minimum: 0.2)
        #expect(raised > 0.2)
        let shown = 0.9 * (1 - raised) + black * raised
        #expect(TerminalReadability.contrast(white, shown) >= TerminalReadability.minimumContrast - 0.001)
        // Dark text over a dark picture under a light scrim.
        let light = TerminalReadability.scrimOpacity(background: 0.05, text: 0.02, scrim: 1, minimum: 0)
        #expect(TerminalReadability.contrast(0.02, 0.05 * (1 - light) + light) >= TerminalReadability.minimumContrast - 0.001)
        // A scrim the colour of the text can't help: all of it.
        #expect(TerminalReadability.scrimOpacity(background: 0.9, text: 0.9, scrim: 0.9, minimum: 0) == 1)
    }

    @Test("under light text a backdrop's bright parts are capped so body text keeps 4.5:1 and dim text 2.5:1")
    func ceiling() throws {
        let text = 0.8, scrim = 0.0
        let dim = TerminalReadability.dimLuminance(of: CodableColor(sRGBRed: 0.92, green: 0.92, blue: 0.92))
        #expect(dim < text)
        for opacity in [0.0, 0.35, 0.8] {
            let cap = try #require(TerminalReadability.ceiling(text: text, dim: dim, scrim: scrim, opacity: opacity))
            let shown = cap * (1 - opacity) + scrim * opacity
            #expect(TerminalReadability.contrast(text, shown) >= TerminalReadability.minimumContrast - 0.001)
            #expect(TerminalReadability.contrast(dim, shown) >= TerminalReadability.minimumDimContrast - 0.001)
        }
        #expect(TerminalReadability.ceiling(text: text, dim: dim, scrim: scrim, opacity: 0.8)!
                > TerminalReadability.ceiling(text: text, dim: dim, scrim: scrim, opacity: 0.35)!,
                "more scrim, less to cap")
        #expect(TerminalReadability.ceiling(text: 0.02, dim: 0.01, scrim: 1, opacity: 0.3) == nil,
                "dark text over a light scrim: the scrim does it")
    }

    // MARK: - Shaders and motion

    @Test("the backdrops' shaders are compiled into the module")
    func shaders() throws {
        let url = try #require(TerminalBackdropView.shaderBundle.url(forResource: "default", withExtension: "metallib"))
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(URL: url)
        for function in ["glassRain", "glassSynthwave", "glassPixelate", "glassDuotone", "glassScanlines", "glassPhosphorScreen",
                         "glassCeiling"] {
            #expect(library.functionNames.contains(function), "\(function)")
        }
    }

    @Test("output makes the terminal active until it has been quiet a while")
    func outputActivity() async {
        let activity = SwiftTermOutputActivity()
        activity.quiet = .milliseconds(100)
        #expect(!activity.isActive)
        activity.note()
        #expect(activity.isActive)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(activity.isActive, "not yet quiet")
        // Under the whole suite's load the main actor can be held for seconds: wait for the watch to
        // run rather than for a fixed time.
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while activity.isActive, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(!activity.isActive, "quiet")
    }

    @Test("the backdrop's clock eases into a new speed rather than jumping")
    func clock() {
        let clock = TerminalBackdropClock()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = clock.time(at: start, speed: 1)
        let first = clock.time(at: start.addingTimeInterval(0.1), speed: 4)
        #expect(first > 0.1 && first < 0.4, "between the old speed and the new: \(first)")
        let paused = clock.time(at: start.addingTimeInterval(3_600), speed: 1)
        #expect(paused - first < 2, "an hour asleep doesn't fast-forward")
    }
}
