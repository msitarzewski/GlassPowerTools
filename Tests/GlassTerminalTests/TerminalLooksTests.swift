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

    @Test("the newer looks: the coding agent, aurora, starfield and blueprint")
    func newerPresets() {
        let window = GlassWindowOverrides()
        let agent = TerminalLookStyle.resolved(TerminalLookPreset.agent.applied(to: window))
        #expect(agent.backdrop == .agent && agent.glowColor == .agent && agent.glow > 0)
        #expect(agent.usesAgent)
        let aurora = TerminalLookStyle.resolved(TerminalLookPreset.aurora.applied(to: window))
        #expect(aurora.backdrop == .aurora && aurora.phosphor == .none && !aurora.usesAgent)
        let starfield = TerminalLookStyle.resolved(TerminalLookPreset.starfield.applied(to: window))
        #expect(starfield.backdrop == .starfield)
        let blueprint = TerminalLookStyle.resolved(TerminalLookPreset.blueprint.applied(to: window))
        #expect(blueprint.backdrop == .blueprint && blueprint.phosphor == .blueprint)
        #expect(TerminalPhosphor.blueprint.isMonochrome, "one pen colour for all the text")
        #expect(!TerminalBackdropStyle.blueprint.isAnimated)

        // Quicken with Output is for the backdrops that have a speed to change.
        #expect(Set(TerminalBackdropStyle.allCases.filter(\.quickensWithOutput)) == [.rain, .aurora, .starfield])
        // Every moving backdrop stops under Reduce Motion: it says it moves.
        for style in [TerminalBackdropStyle.agent, .aurora, .starfield] { #expect(style.isAnimated, "\(style)") }
    }

    @Test("the Coding Agent look draws only where an agent runs, in that agent's colour")
    func agentLook() throws {
        var window = GlassWindowOverrides()
        window = TerminalLookPreset.agent.applied(to: window)
        let style = TerminalLookStyle.resolved(window)
        #expect(!style.drawsBackdrop(agent: nil), "no agent, nothing behind the text")
        #expect(style.drawsBackdrop(agent: .claudeCode))
        window[TerminalWindowSettings.backdropIntensity] = 0
        #expect(!TerminalLookStyle.resolved(window).drawsBackdrop(agent: .claudeCode), "faded out entirely")

        // Another look draws as it always has, agent or none.
        let rain = TerminalLookStyle.resolved(TerminalLookPreset.digitalRain.applied(to: GlassWindowOverrides()))
        #expect(rain.drawsBackdrop(agent: nil) && rain.drawsBackdrop(agent: .codex))
        #expect(!rain.usesAgent, "so the agent is never looked for")

        let text = CodableColor(sRGBRed: 0.9, green: 0.9, blue: 0.9)
        let claude = try #require(TerminalAgent.claudeCode.accent)
        #expect(TerminalGlowColor.agent.color(text: text, agent: .claudeCode) == claude)
        #expect(TerminalGlowColor.agent.color(text: text, agent: nil) == text, "no agent: the text's colour")
        #expect(TerminalGlowColor.agent.color(text: text, agent: .cursor) == text, "a black mark: the text's colour")
        #expect(TerminalGlowColor.cyan.color(text: text, agent: .claudeCode) != claude, "only Agent's Color follows it")
    }

    @Test("an agent's colour is the Agency Agents app's")
    func agentColours() throws {
        func hex(_ color: CodableColor?) -> String? {
            color.map { String(format: "%02X%02X%02X", Int(($0.red * 255).rounded()), Int(($0.green * 255).rounded()),
                               Int(($0.blue * 255).rounded())) }
        }
        #expect(hex(TerminalAgent.claudeCode.accent) == "D97757")
        #expect(hex(TerminalAgent.codex.accent) == "10A37F")
        #expect(hex(TerminalAgent.geminiCLI.accent) == "4285F4")
        #expect(hex(TerminalAgent.mistralVibe.accent) == "FA520F")
        #expect(TerminalAgent.cursor.accent == nil && TerminalAgent.kimi.accent == nil, "black marks")
        for agent in TerminalAgent.allCases { #expect(agent.accent?.isValid ?? true, "\(agent)") }
    }

    @Test("the agent's smoke keeps its corners and edges in place, so it always fills its frame")
    func agentSmoke() {
        for time in stride(from: 0.0, through: 120, by: 7.3) {
            let points = TerminalAgentBackdrop.points(at: time)
            #expect(points.count == 9)
            #expect(points[0] == [0, 0] && points[2] == [1, 0] && points[6] == [0, 1] && points[8] == [1, 1])
            #expect(points[1].y == 0 && points[7].y == 1 && points[3].x == 0 && points[5].x == 1, "edges on their edges")
            #expect(points.allSatisfy { (-0.01...1.01).contains($0.x) && (-0.01...1.01).contains($0.y) })
        }
        #expect(TerminalAgentBackdrop.points(at: 0)[4] != TerminalAgentBackdrop.points(at: 3)[4], "the middle drifts")
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

    @Test("contrast is WCAG 2's: AA is 4.5:1, and the published answers come out")
    func wcagContrast() {
        #expect(TerminalReadability.minimumContrast == 4.5)
        #expect(TerminalReadability.minimumDimContrast == 2.5)
        #expect(TerminalReadability.contrast(1, 0) == 21)
        // #767676 is the lightest grey that passes AA on white (4.54:1); #777777 does not (4.48:1).
        let passing = TerminalReadability.luminance(red: 118 / 255, green: 118 / 255, blue: 118 / 255)
        let failing = TerminalReadability.luminance(red: 119 / 255, green: 119 / 255, blue: 119 / 255)
        #expect(abs(TerminalReadability.contrast(1, passing) - 4.54) < 0.005)
        #expect(abs(TerminalReadability.contrast(1, failing) - 4.48) < 0.005)
    }

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
                         "glassCeiling", "glassAurora", "glassStarfield", "glassBlueprint", "glassWorkingRipple"] {
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

    @Test("Blur softens a picture along the whole slider: a quarter barely, half still shows it, Soft as before")
    func pictureBlurRamp() {
        let radius = TerminalBackdropView.pictureBlurRadius
        #expect(radius(0) == 0)
        #expect(radius(1) == 30)
        #expect(radius(0.25) < 1, "a quarter softens, no more")
        #expect(radius(0.5) < 5, "at half the picture still shows; it was 15 points, and gone")
        #expect(radius(0.75) > 2 * radius(0.5), "the softening keeps growing toward Soft")
        let steps = stride(from: 0.0, through: 1, by: 0.05).map(radius)
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 }, "every step softens more")
        #expect(radius(-1) == 0 && radius(2) == 30, "out of range is held to the slider's ends")
    }
}
