#if os(macOS)
import Foundation
import Testing
@testable import GlassTerminal

/// Terminal tabs on the Mac: named by what the shell says unless someone names them, and renamable
/// with the name kept across a relaunch (2026-10-07).
@MainActor
@Suite("Mac terminal tab names")
struct MacWorkspaceTabNamingTests {
    @Test("the automatic name: the title the shell set, else the directory, else nothing")
    func automatic() {
        let home = "/Users/ann"
        #expect(MacWorkspaceTabNaming.automaticTitle(.init(title: "vim notes.md", directory: "/Users/ann/src"), home: home) == "vim notes.md")
        #expect(MacWorkspaceTabNaming.automaticTitle(.init(title: "  ", directory: "/Users/ann/src/app"), home: home) == "app")
        #expect(MacWorkspaceTabNaming.automaticTitle(.init(title: nil, directory: home), home: home) == "~")
        #expect(MacWorkspaceTabNaming.automaticTitle(.init(title: nil, directory: "/"), home: home) == "/")
        #expect(MacWorkspaceTabNaming.automaticTitle(.init(title: nil, directory: "relative"), home: home) == nil)
        #expect(MacWorkspaceTabNaming.automaticTitle(nil, home: home) == nil)
        #expect(MacWorkspaceTabNaming.abbreviated("/Users/ann/src/app", home: home) == "~/src/app")
        #expect(MacWorkspaceTabNaming.abbreviated("/Users/annie", home: home) == "/Users/annie")
        #expect(MacWorkspaceTabNaming.abbreviated("/etc", home: home) == "/etc")
    }

    @Test("two local tabs in different directories are told apart, and the subtitle says where")
    func localTabsDiffer() throws {
        let suite = "MacWorkspaceTabNamingTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tab = MacWorkspaceController(workspaceID: UUID(), defaults: defaults)
        tab.paneContextInterval = .zero
        let pane = try #require(tab.focusedPaneID)
        #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann")
                == MacWorkspaceWindowIdentity(title: "Local", subtitle: "ann@localhost"))

        tab.updatePaneContext(title: nil, directory: "/Users/ann", for: pane)
        #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann")
                == MacWorkspaceWindowIdentity(title: "~", subtitle: "ann@localhost"),
                "the folder is not said twice")

        tab.updatePaneContext(title: nil, directory: "/Users/ann/src/app", for: pane)
        #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann")
                == MacWorkspaceWindowIdentity(title: "app", subtitle: "~/src/app"))

        tab.updatePaneContext(title: "htop", directory: "/Users/ann/src/app", for: pane)
        #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann").title == "htop")

        tab.rename(to: "  Builds ")
        #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann").title == "Builds",
                "a name someone gave wins over the shell's")
        tab.rename(to: "")
        #expect(tab.tabLabel == nil)
        #expect(tab.windowIdentity(servers: [], localUsername: "ann", home: "/Users/ann").title == "htop")
    }

    @Test("an animated title renames the tab at most once an interval, ending on the latest")
    func throttled() async throws {
        let suite = "MacWorkspaceTabNamingTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tab = MacWorkspaceController(workspaceID: UUID(), defaults: defaults)
        tab.paneContextInterval = .milliseconds(100)
        let pane = try #require(tab.focusedPaneID)
        tab.updatePaneContext(title: "✳ Claude Code", directory: "/tmp", for: pane)
        #expect(tab.paneContextByPaneID[pane]?.title == "✳ Claude Code", "the first change shows at once")
        for frame in ["✶ Working", "✻ Working", "✽ Working"] {
            tab.updatePaneContext(title: frame, directory: "/tmp", for: pane)
        }
        #expect(tab.paneContextByPaneID[pane]?.title == "✳ Claude Code", "frames inside the interval wait")
        for _ in 0..<50 where tab.paneContextByPaneID[pane]?.title != "✽ Working" {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(tab.paneContextByPaneID[pane]?.title == "✽ Working", "the latest frame shows when the interval ends")
    }

    @Test("an SSH tab is named by the remote title, else the remote directory, else the server")
    func sshTab() throws {
        let suite = "MacWorkspaceTabNamingTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")
        let tab = MacWorkspaceController(workspaceID: UUID(), defaults: defaults)
        tab.paneContextInterval = .zero
        tab.addPane(intent: .ssh(serverID: server.id), axis: .horizontal)
        let pane = try #require(tab.focusedPaneID)
        #expect(tab.windowIdentity(servers: [server]).title == "alpha")
        tab.updatePaneContext(title: nil, directory: "/var/www", for: pane)
        #expect(tab.windowIdentity(servers: [server]).title == "www")
        tab.updatePaneContext(title: "ann@alpha: ~/src", directory: "/var/www", for: pane)
        #expect(tab.windowIdentity(servers: [server]).title == "ann@alpha: ~/src")
        #expect(tab.windowIdentity(servers: [server]).subtitle == "ann@192.0.2.10:22", "the machine is still said")
    }

    @Test("a renamed tab keeps its name when the window is restored")
    func renameSurvivesRestore() throws {
        let suite = "MacWorkspaceTabNamingTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let request = MacWorkspaceLaunchRequest()
        let window = MacWorkspaceWindowController(request: request, defaults: defaults)
        window.renameTab(window.selectedTab.workspaceID, to: "Deploys")
        let restored = MacWorkspaceWindowController(request: request, defaults: defaults)
        #expect(restored.selectedTab.tabLabel == "Deploys")

        restored.renameTab(restored.selectedTab.workspaceID, to: nil)
        let again = MacWorkspaceWindowController(request: request, defaults: defaults)
        #expect(again.selectedTab.tabLabel == nil)
    }
}
#endif
