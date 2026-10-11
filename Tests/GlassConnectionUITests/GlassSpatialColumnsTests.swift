//
//  GlassSpatialColumnsTests.swift
//  Glass Power Tools — GlassConnectionUITests
//
//  Our own sidebar and content columns on the headset (W33). The owner, on the Vision Pro
//  (2026-10-10), asked whether Connections, the database, the editor and Files should be completely
//  clear at Glass 0 by giving up Apple's split view, and chose "Yes, all four". The views are
//  visionOS-only and are judged from captures; what can be held still here is their geometry, and
//  that each window still uses them, so a navigation container — whose system glass nothing can
//  clear (D60) — does not come back unnoticed.
//

import Foundation
import SwiftUI
import Testing
@testable import GlassConnectionUI

@Suite("Our own columns on the headset")
struct GlassSpatialColumnsTests {
    @Test func theSidebarKeepsTheSplitViewsIdealWidthAndNarrowsOnlyForANarrowWindow() {
        #expect(GlassSpatialColumns.sidebarWidth(windowWidth: 960) == 360,
                "Connections' first 960 points: the 360 its split view's sidebar had")
        #expect(GlassSpatialColumns.sidebarWidth(windowWidth: 1400) == 360,
                "a wide window does not widen it: nothing here resizes a column")
        #expect(GlassSpatialColumns.sidebarWidth(windowWidth: 900) == 338)
        #expect(GlassSpatialColumns.sidebarWidth(windowWidth: 600) == GlassSpatialColumns.sidebarMinimumWidth,
                "never narrower than the split view allowed")
        #expect(GlassSpatialColumns.sidebarWidth(windowWidth: 0) == GlassSpatialColumns.sidebarIdealWidth)
        #expect(GlassSpatialColumns.sidebarWidth(windowWidth: .nan) == GlassSpatialColumns.sidebarIdealWidth)
        #expect(GlassSpatialColumns.sidebarMinimumWidth == 320 && GlassSpatialColumns.sidebarMaximumWidth == 460)
    }

    @Test func everyColumnsTitleSitsInAHeaderTheSystemBarsHeight() {
        // Measured over the system's bars in the visionOS 27 simulator: the title centred 46
        // points below the window's top, so every header the same height keeps titles level.
        #expect(GlassSpatialColumns.headerHeight == 92)
        #expect(GlassSpatialColumns.titleInset == GlassWindowShape.spatialColumnTitleInset,
                "a content column's title starts where its content does (6d132e9)")
        #expect(GlassSpatialColumns.sidebarTitleInset > GlassSpatialColumns.titleInset,
                "the sidebar's title sits a little further in, as the system's sidebar sets it")
    }

    @Test func aPushedScreenComesInFromTheTrailingEdgeAndBackFromTheLeading() {
        #expect(GlassSpatialColumns.pushEdge(fromDepth: 1, toDepth: 2) == .trailing, "into a folder")
        #expect(GlassSpatialColumns.pushEdge(fromDepth: 2, toDepth: 1) == .leading, "back to its parent")
        #expect(GlassSpatialColumns.pushEdge(fromDepth: 1, toDepth: 1) == .trailing, "across, as a stack replaces")
    }

    // MARK: - Each window still draws its own columns on the headset

    /// The window, the file that lays it out on the headset, and what it must use there.
    static let adopters: [(window: String, file: String, uses: [String])] = [
        ("Connections", "GlassConnectionLibrary.swift", ["GlassSpatialSplitView(visibility: $columnVisibility)",
                                                        "glassSpatialColumn(projection.title(for: scope)"]),
        ("the database", "DatabaseWorkspaceView.swift", ["GlassSpatialSplitView(visibility: $columnVisibility)",
                                                         ".glassSpatialColumn(detailTitle)"]),
        ("the editor", "GlassEditorWorkspaceView.swift", ["GlassSpatialSplitView(visibility: $columnVisibility",
                                                          ".glassSpatialColumn(detailTitle)",
                                                          ".glassSpatialColumn(\"Files\""]),
        ("Files", "SFTPBrowserView.swift", [".glassSpatialColumn(location.name",
                                            ".glassSpatialPush(currentPath, depth: navigationStack.count)"]),
        ("the database's schema", "SchemaBrowserView.swift", [".glassSpatialColumn(title"]),
    ]

    @Test func eachWindowLaysOutItsOwnColumnsOnTheHeadset() throws {
        let sources = try swiftSources()
        for adopter in Self.adopters {
            let file = try #require(sources.first { $0.lastPathComponent == adopter.file },
                                    "\(adopter.window): \(adopter.file) is not in the sources")
            let text = try String(contentsOf: file, encoding: .utf8)
            for uses in adopter.uses {
                #expect(text.contains(uses), """
                    \(adopter.window) no longer draws its own columns on the headset (\(uses) in \
                    \(adopter.file)). A navigation container there draws system glass that Glass \
                    cannot clear (D60, W33).
                    """)
            }
        }
    }

    private func swiftSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)      // …/Tests/GlassConnectionUITests/this file
            .deletingLastPathComponent()                 // …/Tests/GlassConnectionUITests
            .deletingLastPathComponent()                 // …/Tests
            .deletingLastPathComponent()                 // the project
        var files: [URL] = []
        for directory in ["Sources", "App"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(directory),
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        #expect(files.count > 100, "Expected to read the app's sources; found \(files.count) files.")
        return files
    }
}
