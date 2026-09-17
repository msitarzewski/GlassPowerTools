//
//  MenuBarPlacementTests.swift
//  Glass Power Tools — GlassShellTests
//
//  The menu bar is the one surface three merged apps still share, and nothing else can see it.
//
//  `CommandGroup(replacing:)` does not merge. When two scenes replace the same placement SwiftUI
//  keeps one of them and the other simply is not there — no warning, no failure, nothing to notice
//  at runtime except a shortcut that does nothing. On 2026-09-16 the database's File group and the
//  terminal's both replaced `.newItem`; the database's won, and `New Terminal Window`, `New
//  Terminal Tab` and `Connect Saved Host…` were absent from the shipped menu bar. The user reported
//  it as "Command-T doesn't work".
//
//  No unit test can instantiate a `Commands` tree and read back what the menu bar became, and no
//  test that builds a view can either — the loss happens when SwiftUI merges scenes in a running
//  app. So this reads the source, which is where the mistake is actually made and the only place
//  it is visible before someone installs the build and presses the key.
//

import Foundation
import Testing

@Suite("Menu bar placements")
struct MenuBarPlacementTests {

    /// Who replaces what, recorded deliberately.
    ///
    /// Two entries for one placement are safe **only** when they cannot be compiled into the same
    /// menu bar, so each one says which platform it serves. Anything not listed here is a second
    /// owner nobody decided on, which is how ⌘T was lost.
    static let expectedReplacements: [String: Set<String>] = [
        // macOS: the shell owns File ▸ New — one item, aimed by the focused window — and every
        // capability appends to it.
        // visionOS: `PlatformTerminalCommands`, attached only under `#elseif os(visionOS)`
        // (GlassTerminalScenes.swift). The two never exist in the same process.
        "newItem": ["GlassShellFileCommands.swift", "glas_shApp.swift"],
    ]

    @Test func onlyTheRecordedScopesReplaceACommandGroupPlacement() throws {
        var owners: [String: Set<String>] = [:]
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for placement in replacedPlacements(in: text) {
                owners[placement, default: []].insert(file.lastPathComponent)
            }
        }
        #expect(owners == Self.expectedReplacements, """
            The set of sources replacing a CommandGroup placement changed. SwiftUI keeps one \
            replacement per placement and silently drops the rest, so a new one removes somebody \
            else's menu items. Contribute with CommandGroup(after:) instead — or, if this really is \
            a deliberate new owner, record it above with the platform that makes it exclusive.
            """)
    }

    /// The same key equivalent may appear more than once only when the items are mutually exclusive
    /// by focus. This checks the one that has actually bitten: ⌘T, the new-tab key.
    @Test func newTabShortcutHasOneOwnerPerCapability() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(#"keyboardShortcut("t", modifiers: .command)"#) else { continue }
            files.append(file.lastPathComponent)
        }
        // The macOS workspace owns ⌘T; visionOS's platform commands own it on that platform. Two
        // files, never the same platform twice.
        #expect(files.sorted() == ["MacWorkspaceCommands.swift", "glas_shApp.swift"],
                "⌘T is declared in \(files.sorted()). Adding another owner makes which one fires a matter of menu order.")
    }

    /// ⌘N has exactly one owner, and it is the shell's contextual item.
    ///
    /// The point of that item is that it is a stub: the focused window supplies its title and its
    /// action. A second ⌘N anywhere — a capability's menu item, or a toolbar button like the
    /// library's old Add Host — makes which one fires depend on menu order and focus, and one of
    /// them will be wrong.
    @Test func commandNHasASingleOwner() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(#"keyboardShortcut("n", modifiers: .command)"#) else { continue }
            files.append(file.lastPathComponent)
        }
        #expect(files == ["GlassShellFileCommands.swift"],
                "⌘N is declared in \(files.sorted()). It belongs to the shell's one File ▸ New item; a window says what it makes by publishing \\.glassNewItem.")
    }

    /// **Nothing declares ⌘W in SwiftUI**, and that is the fix, not an omission.
    ///
    /// AppKit's own File ▸ Close owns that key. A declared ⌘W beside it does not add a second
    /// candidate: read out of the running app on 2026-09-16, one placement had the declared item
    /// dropped entirely, and another had Close silently stripped of its key while the only item
    /// holding ⌘W was disabled — so ⌘W closed nothing anywhere in the app. What a window closes on
    /// ⌘W is registered with `GlassCloseCommandRouter` instead, which intercepts the Close item
    /// itself. Re-declaring the shortcut here would break it again, invisibly.
    @Test func nothingDeclaresCommandWInSwiftUI() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(#"keyboardShortcut("w", modifiers: .command)"#) else { continue }
            files.append(file.lastPathComponent)
        }
        #expect(files.isEmpty,
                "⌘W is declared in \(files.sorted()). AppKit's File ▸ Close owns that key equivalent; declaring it either takes the key off Close or is dropped outright, and either way ⌘W stops working somewhere. Register the action with glassCloseCommandTarget(priority:) instead.")
    }

    /// ⌘O has one owner, for the reason ⌘T and ⌘W each taught once.
    ///
    /// Opening *a file* is the general act and belongs to the editor, whose command runs its own
    /// panel and so works from any window. The database's Open SQL Document… is the specific one
    /// and sits on ⇧⌘O. Two items on one key equivalent do not give the focused window a choice:
    /// one of them is dropped, silently, and which one is not something the source says.
    @Test func commandOHasASingleOwner() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(#"keyboardShortcut("o", modifiers: .command)"#) else { continue }
            files.append(file.lastPathComponent)
        }
        #expect(files == ["GlassEditorScenes.swift"],
                "⌘O is declared in \(files.sorted()). It opens a file; a capability's own Open belongs on a modified key.")
    }

    /// Every window that can answer "what does New make here?" publishes the focused value. A
    /// window that stops publishing does not fail anything at runtime — ⌘N just goes grey.
    @Test func eachWorkspacePublishesWhatNewMakes() throws {
        var publishers: Set<String> = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains(#"\.glassNewItem, GlassNewItemAction"#) {
                publishers.insert(file.lastPathComponent)
            }
        }
        #expect(publishers == ["GlassShellLibraryView.swift", "MacWorkspaceView.swift",
                               "DatabaseWorkspaceView.swift", "GlassEditorWorkspaceView.swift"],
                "The windows publishing \\.glassNewItem changed: \(publishers.sorted()).")
    }

    // MARK: Reading the sources

    /// Line by line, skipping comments — a comment explaining why a placement is *not* replaced any
    /// more is prose, and counting it as an owner would make the test fail on its own explanation.
    private func replacedPlacements(in text: String) -> [String] {
        var found: [String] = []
        let marker = "CommandGroup(replacing:"
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else { continue }
            var rest = Substring(code)
            while let start = rest.range(of: marker) {
                let tail = rest[start.upperBound...]
                guard let end = tail.firstIndex(of: ")") else { break }
                let argument = tail[..<end]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "CommandGroupPlacement.", with: "")
                found.append(argument.hasPrefix(".") ? String(argument.dropFirst()) : argument)
                rest = tail[end...]
            }
        }
        return found
    }

    /// `Sources` and `App`, found from this file rather than from the working directory, so the
    /// test does not depend on where it was launched.
    private func swiftSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)      // …/Tests/GlassShellTests/this file
            .deletingLastPathComponent()                 // …/Tests/GlassShellTests
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
        // A guard on the guard: an empty sweep would pass every expectation above while proving
        // nothing at all.
        #expect(files.count > 100, "Expected to read the app's sources; found \(files.count) files.")
        return files
    }
}
