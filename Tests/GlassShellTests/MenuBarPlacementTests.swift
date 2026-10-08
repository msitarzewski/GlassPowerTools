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

    /// ⌘O has one owner on the Mac, for the reason ⌘T and ⌘W each taught once.
    ///
    /// Opening a file or a folder is the general act and belongs to the editor, whose File ▸ Open…
    /// runs its own panel and so works from any window. The database's Open SQL Document… is the
    /// specific one and sits on ⇧⌘O. Two items on one key equivalent do not give the focused window
    /// a choice: one of them is dropped, silently, and which one is not something the source says.
    ///
    /// The editor window's toolbar Open… carries ⌘O too, for an iPad or headset keyboard, where
    /// there is no menu bar — and only there: it must sit inside `#if !os(macOS)`, so the Mac never
    /// compiles a second owner.
    @Test func commandOHasASingleOwner() throws {
        let marker = #"keyboardShortcut("o", modifiers: .command)"#
        var files: [String] = []
        var onTheMac: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(marker) else { continue }
            files.append(file.lastPathComponent)
            if declarations(of: marker, in: text).contains(where: { !excludesTheMac($0) }) {
                onTheMac.append(file.lastPathComponent)
            }
        }
        #expect(files.sorted() == ["GlassEditorScenes.swift", "GlassEditorWorkspaceView.swift"],
                "⌘O is declared in \(files.sorted()). It opens files and folders; a capability's own Open belongs on a modified key.")
        #expect(onTheMac == ["GlassEditorScenes.swift"],
                "⌘O reaches the Mac from \(onTheMac.sorted()). There it is File ▸ Open…, alone; a toolbar's ⌘O belongs inside #if !os(macOS).")
    }

    /// ⌥⌘O was Open Project…, and it is gone (2026-10-08): one Open… takes files and folders and
    /// decides by what was chosen. A second open command asked the user to know in advance what the
    /// panel would decide anyway.
    @Test func optionCommandOIsNotDeclared() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(#"keyboardShortcut("o", modifiers: [.command, .option])"#)
                    || text.contains(#"keyboardShortcut("o", modifiers: [.option, .command])"#) else { continue }
            files.append(file.lastPathComponent)
        }
        #expect(files.isEmpty, "⌥⌘O is declared in \(files.sorted()). Open… (⌘O) opens folders as projects.")
    }

    /// ⌘S has one menu owner on a Mac: the shell's File ▸ Save, aimed by `\.glassSaveItem`.
    ///
    /// It was the database's Save SQL Document…, disabled in every other window, so in an editor
    /// ⌘S beeped while the editor's own Save sat on ⌥⌘S (2026-09-25). The two other declarations
    /// are not menu owners on a Mac: the database's item is compiled only for iPad and headset
    /// (`#if !os(macOS)`, where the shell's item does not exist), and the SFTP editor's is a
    /// toolbar button in its own window, which the key window answers before the menu bar.
    @Test func commandSHasASingleMenuOwnerOnTheMac() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(#"keyboardShortcut("s", modifiers: .command)"#) else { continue }
            files.append(file.lastPathComponent)
        }
        #expect(files.sorted() == ["Constants.swift", "GlassShellFileCommands.swift", "SFTPRemoteEditorView.swift"],
                "⌘S is declared in \(files.sorted()). On a Mac it belongs to the shell's File ▸ Save; a window says what it saves by publishing \\.glassSaveItem.")
    }

    /// ⇧⌘E is New Editor Window, alone. Explain Plan shared it, and read out of the running app
    /// (2026-09-25) the Query menu's item had simply lost its key; Explain Plan moved to ⌥⌘E.
    @Test func shiftCommandEHasASingleOwner() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(#"keyboardShortcut("e", modifiers: [.command, .shift])"#) else { continue }
            files.append(file.lastPathComponent)
        }
        #expect(files == ["GlassEditorScenes.swift"],
                "⇧⌘E is declared in \(files.sorted()). It opens a new editor window; give anything else its own key.")
    }

    /// ⌘G is Find Next, the shell's (2026-10-08). It was Terminal Grid, which moved to ⌥⌘G, and
    /// Carousel moved from there to ⌥⇧⌘G. The editor wants ⌘G as much as the terminal, so the key
    /// belongs to no capability: a window says what Find Next does there with `\.glassFindItem`.
    @Test func commandGHasASingleOwner() throws {
        #expect(try owners(of: "g", modifiers: ["command"]) == ["GlassShellFindCommands.swift"],
                "⌘G is Find Next, the shell's Edit ▸ Find item; a window aims it by publishing \\.glassFindItem.")
    }

    @Test func shiftCommandGHasASingleOwner() throws {
        #expect(try owners(of: "g", modifiers: ["command", "shift"]) == ["GlassShellFindCommands.swift"],
                "⇧⌘G is Find Previous, the shell's Edit ▸ Find item.")
    }

    @Test func optionCommandGIsTerminalGridAlone() throws {
        #expect(try owners(of: "g", modifiers: ["command", "option"]) == ["MacWorkspaceCommands.swift"],
                "⌥⌘G is Terminal Grid.")
        #expect(try owners(of: "g", modifiers: ["command", "option", "shift"]) == ["MacWorkspaceCommands.swift"],
                "⌥⇧⌘G is Terminal Carousel.")
    }

    /// ⌘F moved with them, from the terminal's Find in Pane… to the shell's Find…. The other two
    /// declarations are not menu owners on a Mac: both are compiled only for iPad and Vision Pro
    /// (`#if !os(macOS)`), where the shell's item does not exist — the terminal's hardware-keyboard
    /// Find and the editor's toolbar Find, in windows of their own.
    @Test func commandFHasASingleMenuOwnerOnTheMac() throws {
        #expect(try owners(of: "f", modifiers: ["command"])
                == ["GlassEditorWorkspaceView.swift", "GlassShellFindCommands.swift", "TerminalWindowView.swift"],
                "⌘F is the shell's Edit ▸ Find ▸ Find… on a Mac; a window aims it by publishing \\.glassFindItem.")
    }

    /// Every window with a find bar says so; one that stops publishing makes ⌘F, ⌘G and ⇧⌘G grey.
    @Test func eachWorkspacePublishesWhatFindSearches() throws {
        var publishers: Set<String> = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains(#"\.glassFindItem, GlassFindItemAction("#) {
                publishers.insert(file.lastPathComponent)
            }
        }
        #expect(publishers == ["MacWorkspaceView.swift"],
                "The windows publishing \\.glassFindItem changed: \(publishers.sorted()).")
    }

    /// Every window with something to save says so; one that stops publishing makes ⌘S a beep.
    @Test func eachWorkspacePublishesWhatSaveSaves() throws {
        var publishers: Set<String> = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains(#"\.glassSaveItem"#), text.contains("GlassSaveItemAction(") {
                publishers.insert(file.lastPathComponent)
            }
        }
        #expect(publishers == ["DatabaseWorkspaceView.swift", "GlassEditorWorkspaceView.swift"],
                "The windows publishing \\.glassSaveItem changed: \(publishers.sorted()).")
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

    /// **There is no Workgroups window** (2026-10-08). Resizing it crashed the app four times in
    /// four minutes, and it was a second copy of the library's Workgroups panel. A scene declaring
    /// it, or anything opening it, brings that copy back.
    @Test func nothingDeclaresOrOpensAWorkgroupsWindow() throws {
        var files: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = text.split(separator: "\n").filter {
                !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            }
            if code.contains(where: { $0.contains(#"id: "terminal-workgroups""#) }) {
                files.append(file.lastPathComponent)
            }
        }
        #expect(files.isEmpty,
                "\(files.sorted()) declares or opens a \"terminal-workgroups\" window. Workgroups is the library's panel; open it with GlassTerminalRuntime.showWorkgroups(openWindow:).")
    }

    /// The window's own Window-menu item went with it, and the owner opens Workgroups from there,
    /// so the Window menu says Workgroups itself.
    @Test func theWindowMenuStillOffersWorkgroups() throws {
        var offeredBy: [String] = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("CommandGroup(after: .singleWindowList)"),
               text.contains(#"Button("Workgroups") { runtime.showWorkgroups(openWindow: openWindow) }"#) {
                offeredBy.append(file.lastPathComponent)
            }
        }
        #expect(offeredBy == ["GlassTerminalLibraryEntries.swift"],
                "Window ▸ Workgroups is offered by \(offeredBy.sorted()); it belongs to TerminalLibraryCommands, once.")
    }

    // MARK: Reading the sources

    /// The files declaring `key` with exactly these modifiers, in any order and spelling of the
    /// list — `.command`, `[.command]` and `[.shift, .command]` are all read — sorted.
    /// A declaration with no modifiers is ⌘, as SwiftUI defaults it.
    private func owners(of key: String, modifiers: Set<String>) throws -> [String] {
        var files: Set<String> = []
        for file in try swiftSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if shortcutModifiers(of: key, in: text).contains(modifiers) {
                files.insert(file.lastPathComponent)
            }
        }
        return files.sorted()
    }

    private func shortcutModifiers(of key: String, in text: String) -> [Set<String>] {
        let marker = #"keyboardShortcut(""# + key + #"""#
        var found: [Set<String>] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else { continue }
            var rest = Substring(code)
            while let start = rest.range(of: marker) {
                let tail = rest[start.upperBound...]
                guard let close = tail.firstIndex(of: ")") else { break }
                let arguments = tail[..<close]
                if let label = arguments.range(of: "modifiers:") {
                    let names = arguments[label.upperBound...].split { ",[]. ".contains($0) }.map(String.init)
                    found.append(Set(names))
                } else {
                    found.append(["command"])
                }
                rest = tail[close...]
            }
        }
        return found
    }

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

    /// The compilation conditions around each line declaring `marker`, innermost last: `#if X`
    /// opens `X`, `#elseif Y` and `#else` replace it with what that branch means, `#endif` closes
    /// it. Enough to say whether a declaration can reach the Mac; not a preprocessor.
    private func declarations(of marker: String, in text: String) -> [[String]] {
        var conditions: [String] = []
        var found: [[String]] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let code = line.trimmingCharacters(in: .whitespaces)
            if code.hasPrefix("#if ") {
                conditions.append(String(code.dropFirst(4)))
            } else if code.hasPrefix("#elseif "), !conditions.isEmpty {
                conditions[conditions.count - 1] = String(code.dropFirst(8))
            } else if code.hasPrefix("#else"), let last = conditions.last {
                conditions[conditions.count - 1] = "not (\(last))"
            } else if code.hasPrefix("#endif"), !conditions.isEmpty {
                conditions.removeLast()
            } else if !code.hasPrefix("//"), code.contains(marker) {
                found.append(conditions)
            }
        }
        return found
    }

    /// Whether any of these conditions keeps the code out of a Mac build.
    private func excludesTheMac(_ conditions: [String]) -> Bool {
        conditions.contains { ["!os(macOS)", "not (os(macOS))", "os(iOS)", "os(visionOS)"].contains($0) }
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
