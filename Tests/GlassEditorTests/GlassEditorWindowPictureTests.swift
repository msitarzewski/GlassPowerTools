//
//  GlassEditorWindowPictureTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  An editor window's picture in Show All Windows is the whole window (the owner, 2026-10-29:
//  "stretch wide to fill the card, and show the sidebar too if open!"), drawn just after it is
//  asked and never inside the asker's update, and kept once the window has gone.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import GlassEditor

@MainActor
@Suite("An editor window's picture")
struct GlassEditorWindowPictureTests {
    @Test func theWholeWindowIsDrawnJustAfterItIsAsked() async throws {
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.picture.\(UUID().uuidString)")!)
        #expect(workspace.previewImage() == nil, "no window and no file: nothing")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Color.orange.frame(width: 900, height: 560))
        window.contentView?.layoutSubtreeIfNeeded()
        workspace.pictureWindow = window
        #expect(workspace.previewImage(maxPixelWidth: 450) == nil, "asked: drawn just after, not now")
        await Task.yield()
        let picture = try #require(workspace.previewImage(maxPixelWidth: 450))
        let frame = try #require(window.contentView?.superview)
        #expect(picture.width == 450)
        #expect(abs(Double(picture.height) / Double(picture.width) - frame.bounds.height / frame.bounds.width) < 0.01,
                "the window's shape")

        workspace.pictureWindow = nil
        #expect(workspace.previewImage(maxPixelWidth: 450) != nil, "out of its window, the last picture stays")
    }

    /// macOS 26 keeps a sidebar in its glass, which a drawing of the window leaves out: the card's
    /// file list was empty (the owner, 2026-10-29). Its rows are drawn in where they are.
    @Test func theSidebarsRowsAreInThePicture() async throws {
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.picture.\(UUID().uuidString)")!)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView:
            NavigationSplitView {
                List { ForEach(["AGENTS.md", "README.md", "Sources", "Tests"], id: \.self) { Label($0, systemImage: "doc") } }
            } detail: { Color.black }
            .toolbar { Button("Run", systemImage: "play") {} }
            .frame(width: 900, height: 560))
        window.toolbar = NSToolbar()
        // On screen for its list to draw, but far off it: a test is not to be seen.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(50)) }
        workspace.pictureWindow = window
        _ = workspace.previewImage(maxPixelWidth: 900)
        await Task.yield()
        let picture = try #require(workspace.previewImage(maxPixelWidth: 900))
        if let png = NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]) {
            try? png.write(to: FileManager.default.temporaryDirectory.appending(path: "editor-window-picture.png"))
        }

        // Where the first two rows are, in the picture: some of it is ink, some of it is not.
        let frame = try #require(window.contentView?.superview)
        func lists(_ view: NSView) -> [NSTableView] { ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap(lists) }
        let list = try #require(lists(frame).first)
        let rows = list.convert(list.rect(ofRow: 0).union(list.rect(ofRow: 1)), to: frame)
        let scale = CGFloat(picture.width) / frame.bounds.width
        let data = try #require(picture.dataProvider?.data as Data?)
        let perRow = picture.bytesPerRow
        var shades = Set<UInt8>()
        for y in Int(rows.minY * scale)..<Int(rows.maxY * scale) {
            // The picture's rows run from its top; the frame's from its bottom.
            let line = picture.height - 1 - y
            // Alpha: the sidebar's glass is not in the picture, so where no row is drawn is clear.
            for x in Int(rows.minX * scale)..<Int(rows.maxX * scale) { shades.insert(data[line * perRow + x * 4 + 3]) }
        }
        #expect(shades.count > 8, "the rows' text is drawn: \(shades.count) shades")
    }

    /// The sidebar's Filter field: its glass drew as a solid white bar in a dark window (the owner,
    /// 2026-10-29: "The search bar is bright"). Where no word or magnifier is, it is faint.
    @Test func theFilterFieldIsNotASolidWhiteBar() async throws {
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.picture.\(UUID().uuidString)")!)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView:
            NavigationSplitView {
                List { ForEach(["AGENTS.md", "README.md"], id: \.self) { Label($0, systemImage: "doc") } }
                    .searchable(text: .constant(""), placement: .sidebar, prompt: "Filter")
            } detail: { Color.black }
            .toolbar { Button("Run", systemImage: "play") {} }
            .frame(width: 900, height: 560))
        window.toolbar = NSToolbar()
        // On screen for its list to draw, but far off it: a test is not to be seen.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(50)) }
        workspace.pictureWindow = window
        _ = workspace.previewImage(maxPixelWidth: 900)
        await Task.yield()
        let picture = try #require(workspace.previewImage(maxPixelWidth: 900))
        if let png = NSBitmapImageRep(cgImage: picture).representation(using: .png, properties: [:]) {
            try? png.write(to: FileManager.default.temporaryDirectory.appending(path: "editor-window-picture-dark.png"))
        }

        let frame = try #require(window.contentView?.superview)
        func fields(_ view: NSView) -> [NSSearchField] { ((view as? NSSearchField).map { [$0] } ?? []) + view.subviews.flatMap(fields) }
        let field = try #require(fields(frame).first)
        let box = field.convert(field.bounds, to: frame)
        let scale = CGFloat(picture.width) / frame.bounds.width
        // Past the placeholder, before the end's rounding, halfway up.
        let x = Int((box.minX + box.width * 0.88) * scale)
        let line = picture.height - 1 - Int(box.midY * scale)
        let data = try #require(picture.dataProvider?.data as Data?)
        let pixel = line * picture.bytesPerRow + x * 4
        #expect(!(data[pixel] > 230 && data[pixel + 3] > 230), "not opaque white: r \(data[pixel]) a \(data[pixel + 3])")
    }
}
#endif
