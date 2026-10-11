//
//  GlassWindowShapeTests.swift
//  Glass Power Tools — GlassConnectionUITests
//
//  A plain visionOS window has no shape of its own. Files and the editor painted their theme
//  colour into its square bounds, and the owner saw dark square corners around every one of
//  them on the Vision Pro (2026-10-09). These pin the shape the paint takes, and keep a record of
//  every plain window and what gives it its shape, so a new one is a decision rather than a
//  surprise found on the headset.
//

import Foundation
import SwiftUI
import Testing
@testable import GlassConnectionUI

@Suite("A Glass window keeps the system's shape")
struct GlassWindowShapeTests {
    @Test func paintThatFillsAPlainHeadsetWindowHasTheWindowsCorners() {
        let radius = GlassWindowShape.paintCornerRadius(spatial: true, insetForOrnaments: false)
        // Square paint is the defect: it filled the window's bounds past the rounded glass.
        #expect(radius > 0, "a square paint layer shows as dark corners outside the window's glass")
        #expect(radius == GlassWindowShape.spatialWindowCornerRadius)
        #expect(radius == 46, "the corner traced over the system's own window glass (visionOS 27.2)")
    }

    @Test func aCanvasInsetForItsOrnamentsIsConcentricWithTheWindow() {
        // The terminal and the desktop sit inset for their title and control ornaments, as a
        // rounded card. A paint layer behind that card has the card's corner, not the window's,
        // or its square or over-round edges show beside the card (Reduce Transparency paints it
        // opaque).
        let radius = GlassWindowShape.paintCornerRadius(spatial: true, insetForOrnaments: true)
        #expect(radius == GlassWindowShape.spatialWindowCornerRadius - GlassWindowShape.spatialCanvasInset)
        #expect(radius == 24, "the corner the canvas card already draws (GlassCanvasBackdrop)")
    }

    @Test func offTheHeadsetTheWindowShapesItsOwnContent() {
        // A Mac or iPad window rounds and clips what it holds; the paint stays edge to edge.
        #expect(GlassWindowShape.paintCornerRadius(spatial: false, insetForOrnaments: false) == 0)
        #expect(GlassWindowShape.paintCornerRadius(spatial: false, insetForOrnaments: true) == 0)
    }

    // MARK: - Every plain window, and what shapes it

    /// Each scene declared `.windowStyle(.plain)`, by the `id:` it is declared with, and what keeps
    /// its content inside the window's rounded shape and gives it its glass. `frame` names a source
    /// file and the shared framing it must use, every one of `uses`; `nil` says why the window
    /// needs none.
    ///
    /// Anything plain and not listed here is a window nobody has decided the shape of — which is
    /// how Files and the editor shipped with square corners. W28 (2026-10-10): a plain window
    /// either draws Apple's glass itself (`glassSpatialWindowGlass`, as strong as its Glass, none at
    /// 0) or holds a navigation container whose own system glass is the window's, and then paints
    /// its content as a canvas in the corner nested in Apple's and draws no glass under it.
    /// W32 (2026-10-10): a navigation window has no canvas any more — its `GlassLayeredWindow`
    /// paints Opacity behind the columns, edge to edge in the window's own shape, as its kind's
    /// `GlassNavigationWindowOpacity` says, and the columns' glass is tinted by it.
    static let plainWindows: [String: (frame: (file: String, uses: [String])?, why: String)] = [
        "\"terminal\"": (("VisionTerminalWorkgroupView.swift", [".glassSpatialWindowGlass(strength:"]),
                         "it draws Apple's glass itself, in Apple's corner, as strong as its Blur, so it can be clear"),
        "\"sftp\"": (("GlassTerminalScenes.swift",
                      ["GlassLayeredWindow(paintsTheme: GlassWindowGlass.paintsTheme(SFTPBrowserView.navigationOpacity)) {"]),
                     "the browser's NavigationStack draws the window's glass; Opacity paints the window behind it, in the window's shape"),
        "GlassEditorRuntime.windowID": (("GlassEditorWorkspaceView.swift",
                                         ["GlassLayeredWindow(paintsTheme: GlassWindowGlass.paintsTheme(GlassEditorWorkspace.navigationOpacity)) {"]),
                                        "the split view draws the window's glass; Opacity paints the window behind it, in the window's shape"),
        "\"desktop-session\"": (("DesktopSessionView.swift",
                                 [".glassSpatialWindowGlass(strength:", "GlassWindowShape.spatialNestedCanvasCornerRadius"]),
                                "it draws Apple's glass itself; the remote screen is its canvas, nested in Apple's corner"),
        // W30: a display's own window is the same session view, onto one display.
        "DesktopDisplayWindowValue.windowID": (("DesktopSessionView.swift",
                                                [".glassSpatialWindowGlass(strength:", "GlassWindowShape.spatialNestedCanvasCornerRadius"]),
                                               "a display's window is the desktop's session view: the same glass and canvas"),
        "\"database-workspace\"": (("DatabaseWorkspaceView.swift",
                                    ["GlassLayeredWindow(paintsTheme: GlassWindowGlass.paintsTheme(Self.navigationOpacity)) {",
                                     ".glassSpatialWindowGlass(strength:"]),
                                   "the split view draws the window's glass and Opacity paints the window behind it, in the window's shape; without the split view (DatabaseSpatialLayout) it draws Apple's glass itself"),
        "\"minimized\"": (nil, "an icon in a circle; there is no window surface to shape"),
    ]

    @Test func everyPlainWindowIsRecordedWithWhatShapesIt() throws {
        let sources = try swiftSources()
        var found: Set<String> = []
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for id in plainSceneIDs(in: text) { found.insert(id) }
        }
        #expect(found == Set(Self.plainWindows.keys), """
            The windows declared `.windowStyle(.plain)` changed. A plain visionOS window has no \
            shape of its own: say what keeps this one's content inside the window's rounded corners \
            (GlassLayeredWindow or GlassNativeWindowFrame paint in GlassWindowShape's corner), or \
            use the system's window. Found: \(found.sorted())
            """)

        for (id, entry) in Self.plainWindows {
            guard let frame = entry.frame else { continue }
            let file = try #require(sources.first { $0.lastPathComponent == frame.file },
                                    "\(id): \(frame.file) is not in the sources")
            let text = try String(contentsOf: file, encoding: .utf8)
            for uses in frame.uses {
                #expect(text.contains(uses), "\(id) is plain and no longer framed by \(uses) in \(frame.file)")
            }
        }
    }

    /// The frame the plain windows above rely on paints in that shape. `GlassLayeredWindow` lives
    /// in GlassLayers, which this target cannot render on the headset's terms, so this reads the
    /// line that used to say `cornerRadius: 0`.
    @Test func theSharedFramePaintsInTheWindowsShapeOnTheHeadset() throws {
        let file = try #require(try swiftSources().first { $0.lastPathComponent == "GlassLayeredWindow.swift" })
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("GlassLayerBackground(state: resolved, cornerRadius: paintCornerRadius)"),
                "the layered window's paint no longer takes the shape it is given")
        #expect(text.contains("GlassWindowShape.paintCornerRadius(spatial: true"),
                "the layered window no longer asks for the headset window's shape")
    }

    /// The `id:` of the scene each `.windowStyle(.plain)` belongs to: the nearest `Window(` or
    /// `WindowGroup(` declaration above it. Comments that mention the style are not scenes.
    private func plainSceneIDs(in text: String) -> [String] {
        // `\b` so `openWindow(id:` and `GlassLayeredWindow(` are not mistaken for a scene.
        let declaration = /\b(?:WindowGroup|Window)\([^\n]*?id:\s*([^,)\s]+)/
        var ids: [String] = []
        var lineStart = text.startIndex
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            defer { lineStart = text.index(lineStart, offsetBy: line.count + 1, limitedBy: text.endIndex) ?? text.endIndex }
            guard let style = line.range(of: ".windowStyle(.plain)") else { continue }
            if let comment = line.range(of: "//"), comment.lowerBound < style.lowerBound { continue }
            let before = text[text.startIndex..<lineStart]
            if let last = before.matches(of: declaration).last {
                ids.append(String(last.output.1))
            } else {
                ids.append("<no scene above: \(line.trimmingCharacters(in: .whitespaces))>")
            }
        }
        return ids
    }

    private func swiftSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)      // …/Tests/GlassConnectionUITests/this file
            .deletingLastPathComponent()                 // …/Tests/GlassConnectionUITests
            .deletingLastPathComponent()                 // …/Tests
            .deletingLastPathComponent()                 // the project
        var files: [URL] = []
        for directory in ["Sources", "App"] {
            let base = root.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in walker where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        // An empty sweep would find no plain windows and fail for the wrong reason, or — worse,
        // with an empty record — pass while proving nothing.
        #expect(files.count > 100, "Expected to read the app's sources; found \(files.count) files.")
        return files
    }
}

/// Nested corners on the headset stay concentric (owner, 2026-10-10: "the mismatched radii
/// bothers me").
@Suite("Concentric corners")
struct GlassConcentricCornerTests {
    @Test func aShapeInsideAnotherKeepsTheSameDistanceRoundTheCorner() {
        #expect(GlassWindowShape.concentricCornerRadius(outer: 24, inset: 10) == 14)
        #expect(GlassWindowShape.concentricCornerRadius(outer: 46, inset: 10) == 36)
        #expect(GlassWindowShape.concentricCornerRadius(outer: 8, inset: 10) == 0, "never below square")
    }
}

/// W28: every plain window's canvas is the terminal's (owner, on the headset, 2026-10-10: "Yep, I
/// like this much better"), and lives in one place.
@Suite("A canvas nested in the window")
struct GlassNestedCanvasTests {
    @Test func theCanvasSitsTheTerminalsEvenDistanceInsideTheWindowInAConcentricCorner() {
        #expect(GlassWindowShape.spatialNestedCanvasInset == 34)
        let r = GlassWindowShape.spatialNestedCanvasCornerRadius
        #expect(r == GlassWindowShape.continuousConcentricCornerRadius(outer: 46, inset: 34))
        #expect(abs(r - 23.75) < 0.01, "46 − 34 / 1.528")
    }

    @Test func theFramePlusThePaddingIsTheSameInsetOnEverySideWhateverTheOrnaments() {
        for (title, controls) in [(true, true), (true, false), (false, true), (false, false)] {
            let padding = GlassWindowShape.spatialNestedCanvasPadding(showsTitle: title, showsControls: controls)
            let side = title || controls ? GlassWindowShape.spatialCanvasInset : 0
            let edge = GlassWindowShape.spatialNestedCanvasInset
            #expect(padding.top + (title ? GlassWindowShape.spatialTitleInset : 0) == edge)
            #expect(padding.bottom + (controls ? GlassWindowShape.spatialControlsInset : 0) == edge)
            #expect(padding.leading + side == edge && padding.trailing + side == edge)
            #expect(padding.top >= 0 && padding.bottom >= 0 && padding.leading >= 0, "a frame inset never exceeds the canvas's")
        }
    }

    /// W32: a column's content lines up with the column's title and keeps the terminal's margin
    /// from the window's edges — Your Library's numbers (6d132e9), shared by the database's and the
    /// editor's pages so every window's content starts in the same place.
    @Test func aColumnsContentStartsAtItsTitleAndKeepsTheTerminalsMarginFromTheWindowsEdges() {
        let insets = GlassWindowShape.spatialColumnContentInsets
        #expect(insets.leading == GlassWindowShape.spatialColumnTitleInset && insets.leading == 24,
                "where visionOS sets a column's navigation title, measured in the visionOS 27 simulator")
        #expect(insets.trailing == GlassWindowShape.spatialNestedCanvasInset && insets.bottom == 34)
        #expect(insets.top == 0, "the column's navigation bar is above it, not the window's edge")
    }
}

@Suite("Continuous concentric corners")
struct GlassContinuousConcentricCornerTests {
    @Test func theInnerCurveBeginsWhereTheOuterBegins() {
        let r = GlassWindowShape.continuousConcentricCornerRadius(outer: 46, inset: 34)
        #expect(abs(r * GlassWindowShape.continuousCornerExtent + 34 - 46 * GlassWindowShape.continuousCornerExtent) < 0.001,
                "both curves meet the straight edge at the same place")
        #expect(GlassWindowShape.continuousConcentricCornerRadius(outer: 10, inset: 100) == 0, "never below square")
    }
}
