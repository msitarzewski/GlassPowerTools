import Foundation
import Testing
@testable import GlassTerminalEmulator

/// A link's actions, the same on the Mac's right-click and a pinch held on the headset (the owner,
/// 2026-10-15: "the vision pro needs the data detector and selection work").
@MainActor
@Suite("A link's actions")
struct TerminalLinkLookupTests {
    private func titles(_ target: TerminalLinkTarget, _ model: SwiftTermHostModel?) -> [String] {
        TerminalLinkLookup.actions(for: target, model: model, copy: { _ in }).map(\.title)
    }

    @Test("an address: Open Link where a ⌘-click may open it, and Copy Link")
    func address() throws {
        let model = SwiftTermHostModel()
        let web = try #require(URL(string: "https://example.com/docs"))
        #expect(titles(.url(web), model) == ["Open Link", "Copy Link"])
        #expect(titles(.url(web), nil) == ["Copy Link"], "nothing to ask the question with")
        let account = try #require(URL(string: "https://ann:secret@example.com/"))
        #expect(titles(.url(account), model) == ["Copy Link"], "an address with an account in it is never opened")
    }

    @Test("a path: what the host can do with it, then Copy Path; a folder is never watched")
    func path() {
        let model = SwiftTermHostModel()
        #expect(titles(.path("/var/log/app.log"), model) == ["Copy Path"], "a host that can do nothing")
        model.onOpenPath = { _ in }
        model.onRevealPath = { _ in }
        model.onWatchFile = { _ in }
        #expect(titles(.path("/var/log/app.log"), model) == ["Open in Editor", "Show in Files", "Watch Log File", "Copy Path"])
        #expect(titles(.path("/var/log/"), model) == ["Open in Editor", "Show in Files", "Copy Path"])
        model.revealPathTitle = "Show in Finder"
        #expect(titles(.path("~/notes"), model).contains("Show in Finder"))
    }

    @Test("Copy copies the link itself")
    func copying() throws {
        var copied: [String] = []
        let actions = TerminalLinkLookup.actions(for: .path("~/logs/app.log"), model: nil, copy: { copied.append($0) })
        try #require(actions.count == 1)
        actions[0].perform()
        #expect(copied == ["~/logs/app.log"])
    }
}
