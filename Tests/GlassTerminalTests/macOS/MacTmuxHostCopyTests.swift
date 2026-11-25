#if os(macOS)
import Foundation
import os
import Testing
@testable import GlassTerminal

/// The host runs from a copy no update replaces (D114, 2026-11-23): an update replaced the app under the running
/// host, macOS's check of it failed, and its terminals lost the app's folder permissions. Since D115 (2026-11-24) the
/// copy is of the small terminal host app inside the app, named by its code's hash. These build small signed apps in a
/// folder of their own, so nothing of the installed app's, or of this Mac's tmux, is touched.
@Suite("Local tmux host's own copy", .serialized)
nonisolated struct MacTmuxHostCopyTests {
    @Test("a copy's name is the start of its code's hash, and a running program's copy is found by its path")
    func names() throws {
        #expect(MacTmuxHostCopy.copyName(codeHash: "b8b16037300a7ac583a926fc") == "host-b8b16037300a")
        let folder = URL(fileURLWithPath: "/tmp/hosts.noindex")
        #expect(MacTmuxHostCopy.copyName(of: "/tmp/hosts.noindex/host-abc/A.app/Contents/MacOS/A", in: folder) == "host-abc")
        #expect(MacTmuxHostCopy.copyName(of: "/tmp/hosts.noindex/0.4.646-abc/A.app/Contents/MacOS/A", in: folder)
                == "0.4.646-abc", "a whole-app copy an earlier version made, so it stays while its host runs")
        #expect(MacTmuxHostCopy.copyName(of: "/Applications/A.app/Contents/MacOS/A", in: folder) == nil)
    }

    @Test("the terminal host app is found in the app's Contents/Helpers, with its executable; none outside an app")
    func helperFound() throws {
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: work) }
        let outer = work + "/Outer.app"
        try FileManager.default.createDirectory(atPath: outer + "/Contents/MacOS", withIntermediateDirectories: true)
        let app = try #require(Bundle(path: outer))
        #expect(MacTmuxHostCopy.helper(of: app) == nil, "an app without one")

        let helper = try Self.makeApp(in: outer + "/Contents/Helpers", returning: 0, name: MacTmuxHostCopy.helperName)
        let found = try #require(MacTmuxHostCopy.helper(of: app))
        #expect(found.bundle.path == helper)
        #expect(found.executable == helper + "/Contents/MacOS/Probe")
        let folder = try #require(Bundle(path: work))
        #expect(MacTmuxHostCopy.helper(of: folder) == nil, "a folder is no app")

        // Its copy's name: its CFBundleName, or its own when it has none or one that would make a path.
        #expect(MacTmuxHostCopy.copyBundleName(of: URL(fileURLWithPath: helper)) == MacTmuxHostCopy.helperName)
        for (bundleName, expected) in [("Glass Power Tools", "Glass Power Tools.app"), ("../x", MacTmuxHostCopy.helperName),
                                       (".hidden", MacTmuxHostCopy.helperName), ("", MacTmuxHostCopy.helperName)] {
            try Self.writeInfo(executable: "Probe", bundleName: bundleName, to: helper)
            #expect(MacTmuxHostCopy.copyBundleName(of: URL(fileURLWithPath: helper)) == expected, "\(bundleName)")
        }

        // An Info.plist naming no executable there, or one outside the bundle, names none.
        try Self.writeInfo(executable: "Missing", to: helper)
        #expect(MacTmuxHostCopy.executable(inBundle: URL(fileURLWithPath: helper)) == nil)
        try Self.writeInfo(executable: "../MacOS/Probe", to: helper)
        #expect(MacTmuxHostCopy.executable(inBundle: URL(fileURLWithPath: helper)) == nil)
    }

    @Test("the copy is made once and checks; an update that leaves the helper as it was keeps it, a changed helper gets its own")
    func copySurvivesAnUpdate() throws {
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: work) }
        let helper = URL(fileURLWithPath: try Self.makeApp(in: work + "/Applications", returning: 0))
        let hosts = URL(fileURLWithPath: work + "/Terminal Host.noindex")
        let hash = try #require(MacTmuxHostCopy.codeHash(of: helper))

        let copy = try #require(MacTmuxHostCopy.executable(of: helper, in: hosts))
        #expect(copy == hosts.path + "/host-\(hash.prefix(12))/Probe.app/Contents/MacOS/Probe")
        #expect(FileManager.default.isExecutableFile(atPath: copy))
        let copyBundle = Self.bundle(of: copy)
        #expect(MacTmuxHostCopy.isIntact(copyBundle))
        #expect(MacTmuxHostCopy.codeHash(of: copyBundle) == hash, "the same code, so macOS knows it as the same app")
        #expect(MacTmuxHostCopy.executable(of: helper, in: hosts) == copy, "made once")

        // An update whose helper is built from the same code: its copy is the one already made.
        try FileManager.default.removeItem(at: helper)
        _ = try Self.makeApp(in: work + "/Applications", returning: 0)
        #expect(MacTmuxHostCopy.codeHash(of: helper) == hash)
        #expect(MacTmuxHostCopy.executable(of: helper, in: hosts) == copy)
        #expect(try FileManager.default.contentsOfDirectory(atPath: hosts.path) == ["host-\(hash.prefix(12))"])

        // An update whose helper changed: the running host's copy stays as it was, and the next server's is new.
        try FileManager.default.removeItem(at: helper)
        _ = try Self.makeApp(in: work + "/Applications", returning: 7)
        #expect(MacTmuxHostCopy.codeHash(of: helper) != hash)
        #expect(MacTmuxHostCopy.isIntact(copyBundle), "the host's copy is untouched")
        #expect(MacTmuxHostCopy.codeHash(of: copyBundle) == hash)
        let newer = try #require(MacTmuxHostCopy.executable(of: helper, in: hosts))
        #expect(newer != copy)
        let keep = try #require(MacTmuxHostCopy.copyName(of: newer, in: hosts))
        MacTmuxHostCopy.removeCopies(in: hosts, keeping: [keep])
        #expect(try FileManager.default.contentsOfDirectory(atPath: hosts.path) == [keep])
    }

    @Test("copies nothing runs from are removed, a running host's stays until it ends, and none when programs can't be listed")
    func unusedCopiesRemoved() throws {
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: work) }
        let hosts = URL(fileURLWithPath: work + "/Terminal Host.noindex")
        // Three helpers in turn, as three updates that changed it leave them, each with its copy made at the app's start.
        var copies: [String] = []
        for (status, sleeping) in [(0, true), (7, false), (9, false)] {
            try? FileManager.default.removeItem(atPath: work + "/Applications/Probe.app")
            let helper = URL(fileURLWithPath: try Self.makeApp(in: work + "/Applications", returning: status, sleeping: sleeping))
            copies.append(try #require(MacTmuxHostCopy.executable(of: helper, in: hosts)))
        }
        let names = copies.compactMap { MacTmuxHostCopy.copyName(of: $0, in: hosts) }
        #expect(Set(names).count == 3)

        // A host started from the first runs from its copy. The temporary folder is reached through a link
        // (/var is /private/var), and macOS names the running program by its real path.
        let host = Process()
        host.executableURL = URL(fileURLWithPath: copies[0])
        try host.run()
        defer { if host.isRunning { host.terminate() } }
        let deadline = ContinuousClock.now + .seconds(15)
        while MacTmuxHostCopy.copiesInUse(in: hosts)?.contains(names[0]) != true, ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(MacTmuxHostCopy.copiesInUse(in: hosts) == [names[0]])

        MacTmuxHostCopy.removeUnusedCopies(in: hosts, keeping: [], running: { nil })
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: hosts.path)) == Set(names),
                "nothing removed when the running programs can't be listed")

        // The third's start: its own copy and the running host's stay; the second's, which nothing runs, goes.
        MacTmuxHostCopy.removeUnusedCopies(in: hosts, keeping: [names[2]])
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: hosts.path)) == [names[0], names[2]])
        #expect(MacTmuxHostCopy.isIntact(Self.bundle(of: copies[0])), "the running host's copy untouched")

        // Once the host has ended, its copy goes too.
        host.terminate()
        host.waitUntilExit()
        MacTmuxHostCopy.removeUnusedCopies(in: hosts, keeping: [names[2]])
        #expect(try FileManager.default.contentsOfDirectory(atPath: hosts.path) == [names[2]])
    }

    @Test("a copy that doesn't check is not used, and is taken away")
    func brokenCopy() throws {
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: work) }
        let helper = URL(fileURLWithPath: try Self.makeApp(in: work + "/Applications", returning: 0))
        let hosts = URL(fileURLWithPath: work + "/Terminal Host.noindex")
        let copy = try #require(MacTmuxHostCopy.executable(of: helper, in: hosts))
        let place = Self.bundle(of: copy).deletingLastPathComponent()
        // Something changes a sealed file in the copy.
        try "changed".write(toFile: place.path + "/Probe.app/Contents/Resources/note.txt", atomically: true, encoding: .utf8)
        #expect(MacTmuxHostCopy.executable(of: helper, in: hosts) == nil, "refused: the host would fail macOS's check")
        #expect(!FileManager.default.fileExists(atPath: place.path), "and removed, so the next start makes it afresh")
        #expect(MacTmuxHostCopy.executable(of: helper, in: hosts) == copy)
    }

    @Test("a new server's host is the helper's copy, run once first; the helper inside the app when no copy can be made")
    func defaultHost() throws {
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: work) }
        let outer = work + "/Outer.app"
        try FileManager.default.createDirectory(atPath: outer + "/Contents/MacOS", withIntermediateDirectories: true)
        _ = try Self.makeApp(in: outer + "/Contents/Helpers", returning: 0, name: MacTmuxHostCopy.helperName,
                             bundleName: "Glass Power Tools")
        let app = try #require(Bundle(path: outer))
        let helper = try #require(MacTmuxHostCopy.helper(of: app))
        let hosts = URL(fileURLWithPath: work + "/Terminal Host.noindex")

        let host = MacTmuxService.defaultHost(helper: helper, folder: hosts)
        #expect(host.hasPrefix(hosts.path + "/host-") && host.hasSuffix("/Glass Power Tools.app/Contents/MacOS/Probe"),
                "the copy carries the app's name, which a folder prompt shows: \(host)")
        #expect(MacTmuxHostCopy.isIntact(Self.bundle(of: host)), "renamed, still as signed")
        #expect(MacTmuxService.defaultHost(helper: helper, folder: nil) == helper.executable, "no Application Support")
        // A folder that can't hold copies: a file where it should be.
        let blocked = URL(fileURLWithPath: work + "/blocked")
        try "a file".write(to: blocked, atomically: true, encoding: .utf8)
        #expect(MacTmuxService.defaultHost(helper: helper, folder: blocked) == helper.executable)

        // The app's start makes the copy ready and leaves nothing else.
        try FileManager.default.removeItem(at: hosts)
        MacTmuxService.prepareHost(bundle: app, folder: hosts)
        let name = try #require(MacTmuxHostCopy.copyName(of: host, in: hosts))
        #expect(try FileManager.default.contentsOfDirectory(atPath: hosts.path) == [name])
    }

    @Test("a copy is run once to start and end before it hosts, once a process; one that won't run isn't used")
    func warm() {
        let path = "/tmp/never-\(UUID().uuidString)/Copy"
        let asked = OSAllocatedUnfairLock(initialState: [[String]]())
        #expect(!MacTmuxHostCopy.warm(path, run: { _, arguments in asked.withLock { $0.append(arguments) }; return nil }),
                "it didn't start: not used")
        #expect(MacTmuxHostCopy.warm(path, run: { _, arguments in asked.withLock { $0.append(arguments) }; return "" }))
        #expect(MacTmuxHostCopy.warm(path, run: { _, _ in Issue.record("run twice"); return nil }), "once a process")
        #expect(asked.withLock { $0 } == [["--tmux-host-ready"], ["--tmux-host-ready"]])
    }

    @Test("anything but a signed bundle has no copy: the host runs from the app")
    func notABundle() throws {
        let work = try Self.folder()
        defer { try? FileManager.default.removeItem(atPath: work) }
        #expect(MacTmuxHostCopy.executable(of: URL(fileURLWithPath: work), in: URL(fileURLWithPath: work + "/hosts")) == nil)
    }

    // MARK: Helpers

    static func folder() throws -> String {
        let folder = NSTemporaryDirectory() + "gpt-hostcopy-" + UUID().uuidString.prefix(8).lowercased()
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        return folder
    }

    /// The bundle a copy's executable is in.
    static func bundle(of executable: String) -> URL {
        URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func writeInfo(executable: String, bundleName: String? = nil, to app: String) throws {
        var info: [String: Any] = ["CFBundleIdentifier": "com.glasspowertools.tests.probe", "CFBundleExecutable": executable,
                                   "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL"]
        info["CFBundleName"] = bundleName
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: app + "/Contents/Info.plist"))
    }

    /// A small app (`Probe.app`, or `name`) whose executable is `Probe`, signed ad hoc with a sealed resource;
    /// `returning` makes builds differ, the same `returning` builds the same code, and `sleeping` keeps it running for
    /// a minute, as a host. `bundleName` is its `CFBundleName`, none by default.
    static func makeApp(in directory: String, returning status: Int, sleeping: Bool = false,
                        name: String = "Probe.app", bundleName: String? = nil) throws -> String {
        let app = directory + "/" + name
        try FileManager.default.createDirectory(atPath: app + "/Contents/MacOS", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: app + "/Contents/Resources", withIntermediateDirectories: true)
        try "a sealed resource".write(toFile: app + "/Contents/Resources/note.txt", atomically: true, encoding: .utf8)
        try writeInfo(executable: "Probe", bundleName: bundleName, to: app)
        let source = directory + "/main.c"
        let body = sleeping ? "#include <unistd.h>\nint main(void) { sleep(60); return \(status); }\n"
                            : "int main(void) { return \(status); }\n"
        try body.write(toFile: source, atomically: true, encoding: .utf8)
        try run("/usr/bin/cc", ["-o", app + "/Contents/MacOS/Probe", source])
        try FileManager.default.removeItem(atPath: source)
        try run("/usr/bin/codesign", ["--force", "--sign", "-", app])
        return app
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(executable) \(arguments.joined(separator: " "))")
    }
}
#endif
