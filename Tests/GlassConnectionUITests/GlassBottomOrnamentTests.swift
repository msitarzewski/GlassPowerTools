//
//  GlassBottomOrnamentTests.swift
//  Glass Power Tools — GlassConnectionUITests
//
//  Every bottom bar on the headset is Apple's toolbar ornament (W31). The owner, on the Vision Pro
//  (2026-10-10), looking at a terminal's bar above Connections': "Why are these different sizes?
//  Let's make them all the smaller apple defaults." The terminal's, the remote desktop's, the
//  terminal overview's, Connections' and the schema diagram's bars were each drawn by hand — a
//  stack of buttons with its own spacing and padding in a glass capsule — and each came out a size
//  of its own. `ToolbarItemGroup(placement: .bottomOrnament)` lets the system size and space the
//  buttons and draw the capsule, the same in every window. This keeps a hand-built bar from coming
//  back unnoticed.
//

import Foundation
import Testing

@Suite("Every bottom bar is Apple's toolbar ornament")
struct GlassBottomOrnamentTests {
    /// Files allowed to draw their own ornament at the bottom of a scene, and why. None today.
    static let handBuiltBottomOrnaments: [String: String] = [:]

    @Test func noSceneDrawsItsOwnBottomBar() throws {
        var found: Set<String> = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if ornamentCalls(in: text).contains(where: { $0.contains(".scene(.bottom)") }) {
                found.insert(file.lastPathComponent)
            }
        }
        #expect(found == Set(Self.handBuiltBottomOrnaments.keys), """
            A bottom ornament drawn by hand comes out a size of its own beside every other \
            window's. Put the controls in `.toolbar { ToolbarItemGroup(placement: .bottomOrnament) \
            { … } }` as separate items (not in a stack, and without `.buttonStyle` or \
            `.labelStyle(.iconOnly)`, which change an item's size there), or record here why this \
            one cannot be. Found: \(found.sorted())
            """)
    }

    @Test func theSweepFindsAHandBuiltBar() {
        // The sweep itself, on the shape the terminal's bar had: a call over two lines.
        let source = """
            content
                .ornament(visibility: shows ? .visible : .hidden,
                          attachmentAnchor: .scene(.bottom)) {
                    controls.glassBackgroundEffect(in: .capsule)
                }
                .ornament(attachmentAnchor: .scene(.top)) { title }
            """
        let calls = ornamentCalls(in: source)
        #expect(calls.count == 2)
        #expect(calls.filter { $0.contains(".scene(.bottom)") }.count == 1)
    }

    /// The arguments of every `.ornament(` call in `text`, from the call to the `{` that opens its
    /// content. A line comment is not a call.
    private func ornamentCalls(in text: String) -> [Substring] {
        let code = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            if let comment = line.range(of: "//") { return line[..<comment.lowerBound] }
            return line
        }.joined(separator: "\n")
        var calls: [Substring] = []
        var rest = code[...]
        while let start = rest.range(of: ".ornament(") {
            let tail = rest[start.upperBound...]
            let end = tail.firstIndex(of: "{") ?? tail.endIndex
            calls.append(tail[..<end])
            rest = tail[end...]
        }
        return calls
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
        // An empty sweep would find no ornaments and pass while proving nothing.
        #expect(files.count > 100, "Expected to read the app's sources; found \(files.count) files.")
        return files
    }
}
