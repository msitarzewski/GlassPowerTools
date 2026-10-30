//
//  GlassEditorGitRenderTests.swift
//  Glass Power Tools — GlassEditorTests
//
//  Pictures of Source Control (2026-10-28), drawn in a window off screen over a repository made
//  for them: each part, a conflict, a side-by-side diff, Blame and a file's History. Run only when
//  asked, with `GLASS_GIT_RENDER` naming the folder for the pictures; they are looked at, not
//  compared.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
import GlassEditorCore
@testable import GlassEditor

@MainActor
@Suite("Git: pictures of Source Control", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["GLASS_GIT_RENDER"] != nil))
struct GlassEditorGitRenderTests {
    private var folder: URL { URL(filePath: ProcessInfo.processInfo.environment["GLASS_GIT_RENDER"] ?? "/dev/null") }

    @discardableResult
    private func git(_ arguments: [String], in root: URL) async throws -> GlassEditorCommandOutput {
        let executable = try #require(GlassEditorLocalGit.executable)
        let path = root.path(percentEncoded: false)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try GlassEditorLocalGit.run(executable, arguments, in: path) })
            }
        }
    }

    private func write(_ text: String, _ name: String, in root: URL) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A small project with a history worth drawing: a feature branch merged, another not, a
    /// tag, a remote, a stash, and — when asked — a merge stopped on a conflict.
    private func makeProject(conflict: Bool) async throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitRender-\(UUID().uuidString)/Weather")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await git(["init", "-q", "-b", "main"], in: root)
        for (key, value) in [("user.name", "Ada Example"), ("user.email", "ada@example.com"), ("commit.gpgsign", "false"),
                             ("tag.gpgsign", "false"), ("core.hooksPath", ".git/hooks")] {
            try await git(["config", key, value], in: root)
        }
        let source = """
            import Foundation

            struct Forecast {
                var city: String
                var high: Int
                var low: Int

                func summary() -> String {
                    "\\(city): \\(high)° / \\(low)°"
                }
            }

            """
        try write(source, "Sources/Forecast.swift", in: root)
        try write("# Weather\n\nA small forecast library.\n", "README.md", in: root)
        try await git(["add", "."], in: root)
        try await git(["commit", "-q", "-m", "Start the forecast library"], in: root)
        try await git(["tag", "-a", "v0.1", "-m", "First release"], in: root)

        try await git(["checkout", "-q", "-b", "feature/units"], in: root)
        try write(source.replacingOccurrences(of: "    var low: Int\n", with: "    var low: Int\n    var unit = \"C\"\n"),
                  "Sources/Forecast.swift", in: root)
        try await git(["commit", "-q", "-am", "Remember the unit of each forecast"], in: root)
        try await git(["checkout", "-q", "main"], in: root)
        try write("# Weather\n\nA small forecast library, in Swift.\n", "README.md", in: root)
        try await git(["commit", "-q", "-am", "Say what the library is written in"], in: root)
        try await git(["merge", "-q", "--no-edit", "feature/units"], in: root)
        try await git(["checkout", "-q", "-b", "experiment/hourly"], in: root)
        try write("struct Hourly {\n    var hours: [Int]\n}\n", "Sources/Hourly.swift", in: root)
        try await git(["add", "."], in: root)
        try await git(["commit", "-q", "-m", "Try an hourly forecast"], in: root)
        try await git(["checkout", "-q", "main"], in: root)

        let remote = root.deletingLastPathComponent().appendingPathComponent("origin.git")
        try await git(["init", "-q", "--bare", "-b", "main", remote.path(percentEncoded: false)], in: root)
        try await git(["remote", "add", "origin", "git@github.com:example/weather.git"], in: root)
        try await git(["remote", "set-url", "--push", "origin", remote.path(percentEncoded: false)], in: root)
        try await git(["config", "remote.origin.url", remote.path(percentEncoded: false)], in: root)
        try await git(["push", "-q", "-u", "origin", "main"], in: root)
        try await git(["config", "remote.origin.url", "git@github.com:example/weather.git"], in: root)

        try write("// a sketch\n", "Sources/Sketch.swift", in: root)
        try await git(["stash", "push", "-q", "--include-untracked", "-m", "Half an idea"], in: root)

        if conflict {
            try await git(["checkout", "-q", "-b", "fix/readme"], in: root)
            try write("# Weather\n\nForecasts for any city.\n", "README.md", in: root)
            try await git(["commit", "-q", "-am", "Describe it by what it does"], in: root)
            try await git(["checkout", "-q", "main"], in: root)
            try write("# Weather\n\nA forecast library for Swift.\n", "README.md", in: root)
            try await git(["commit", "-q", "-am", "Shorter description"], in: root)
            _ = try await git(["merge", "fix/readme"], in: root)
        }
        // Work in progress: one change staged, others not, a new file.
        let current = String(decoding: try Data(contentsOf: root.appendingPathComponent("Sources/Forecast.swift")), as: UTF8.self)
        try write(current.replacingOccurrences(of: "\"\\(city): \\(high)° / \\(low)°\"",
                                               with: "\"\\(city): high \\(high)°, low \\(low)°\""), "Sources/Forecast.swift", in: root)
        try await git(["add", "Sources/Forecast.swift"], in: root)
        try write(current.replacingOccurrences(of: "\"\\(city): \\(high)° / \\(low)°\"",
                                               with: "\"\\(city): high \\(high)°, low \\(low)°\"")
                    .replacingOccurrences(of: "struct Forecast {\n", with: "/// One day's weather in one city.\nstruct Forecast {\n")
                    .replacingOccurrences(of: "    var city: String\n", with: "    var city: String\n    var date: Date\n"),
                  "Sources/Forecast.swift", in: root)
        try write("import Foundation\n\nenum Units {\n    case celsius, fahrenheit\n}\n", "Sources/Units.swift", in: root)
        return root
    }

    private func render(_ view: some View, named name: String, size: CGSize = CGSize(width: 1180, height: 760),
                        dark: Bool = false, wait: Duration = .seconds(2)) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(dark ? Color(white: 0.12) : Color(white: 0.97)))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: wait)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name + ".png"))
    }

    @Test func eachPartOfSourceControl() async throws {
        let root = try await makeProject(conflict: false)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.render.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let repository = try #require(workspace.repositories[project.id])
        await repository.settled()
        let document = try #require(workspace.showSourceControl(.changes, of: project.id))
        await repository.loadReferences()
        await repository.settled()
        for section in GlassEditorSourceControlSection.allCases {
            workspace.gitSections[project.id] = section
            try await render(GlassEditorSourceControlView(workspace: workspace, projectID: project.id, document: document),
                             named: "source-control-\(section.rawValue)", dark: section == .history)
        }
        UserDefaults.standard.set("split", forKey: GlassEditorDiffSettings.layoutKey)
        defer { UserDefaults.standard.removeObject(forKey: GlassEditorDiffSettings.layoutKey) }
        workspace.gitSections[project.id] = .changes
        try await render(GlassEditorSourceControlView(workspace: workspace, projectID: project.id, document: document),
                         named: "source-control-changes-split", dark: true)

        let file = root.appendingPathComponent("Sources/Forecast.swift").path(percentEncoded: false)
        try await render(GlassEditorBlameView(workspace: workspace, projectID: project.id, path: file), named: "blame")
        try await render(GlassEditorFileHistoryView(workspace: workspace, projectID: project.id, path: file),
                         named: "file-history", dark: true)
        try await render(GlassEditorSourceControlView(workspace: workspace, projectID: project.id, document: document),
                         named: "source-control-changes-narrow", size: CGSize(width: 420, height: 760))
    }

    @Test func aMergeStoppedOnAConflict() async throws {
        let root = try await makeProject(conflict: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let workspace = GlassEditorWorkspace(defaults: UserDefaults.forTest(suiteName: "editor.render.\(UUID().uuidString)")!)
        let project = try #require(workspace.openProject(root))
        let repository = try #require(workspace.repositories[project.id])
        await repository.settled()
        let document = try #require(workspace.showSourceControl(.changes, of: project.id))
        await repository.settled()
        try await render(GlassEditorSourceControlView(workspace: workspace, projectID: project.id, document: document),
                         named: "conflict-list")
        try await render(GlassEditorConflictView(workspace: workspace, projectID: project.id, repository: repository,
                                                 path: "README.md") {},
                         named: "conflict-resolve", size: CGSize(width: 900, height: 420))
    }
}
#endif
