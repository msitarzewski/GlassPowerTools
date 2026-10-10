import Foundation
import Testing
import GlassShell
@testable import GlassTerminal

/// W20 (owner, 2026-10-09): "I was testing to see if there was a way to give a color/tint to the
/// tab group." A terminal window owns its look: every tab in it draws with it, a tab moved in
/// takes it, it comes back with the window, and a saved Workgroup carries it to every device.
///
/// Nothing connects: terminals are registered with a manager and moved between workgroups.
@MainActor
@Suite("A terminal window owns its look")
struct TerminalWindowLookTests {
    private let red = TerminalSessionOverride(windowOpacity: 0.4, glassTint: "#FF2D55")
    private let blue = TerminalSessionOverride(blurBackground: 0.2, glassTint: "#007AFF")

    private func server(_ name: String) -> ServerConfiguration {
        var server = ServerConfiguration(name: name, host: "\(name).example.com", username: "ann")
        server.tmux = true
        return server
    }

    private func terminal(_ server: ServerConfiguration, tmux: String? = nil, in manager: SessionManager) -> TerminalSession {
        let session = TerminalSession(server: server)
        session.tmuxSessionName = tmux
        manager.registerSession(session)
        return session
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "TerminalWindowLook.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    private func json(_ preset: LayoutPreset) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as? [String: Any])
    }

    // MARK: How a terminal is drawn

    @Test("each field the window's look sets wins; each it leaves unset follows the terminal settings")
    func resolution() {
        let settings = (frost: "regular", opacity: 0.25, blur: 0.75, interactive: true, tint: "None")
        func resolved(_ look: TerminalSessionOverride?) -> TerminalLook {
            TerminalLook(look: look, frost: settings.frost, opacity: settings.opacity, blur: settings.blur,
                         interactiveGlass: settings.interactive, tint: settings.tint)
        }
        let plain = resolved(nil)
        #expect(plain.frost == "regular" && plain.opacity == 0.25 && plain.blur == 0.75)
        #expect(plain.interactiveGlass && plain.tint == "None" && plain.tintColor == nil && plain.windowBlur == nil)

        let tinted = resolved(red)
        #expect(tinted.tint == "#FF2D55" && tinted.tintColor != nil)
        #expect(tinted.opacity == 0.4, "set by the window")
        #expect(tinted.blur == 0.75 && tinted.windowBlur == nil, "left to the settings")
        #expect(tinted.frost == "regular" && tinted.interactiveGlass)

        let frosted = resolved(TerminalSessionOverride(glassFrost: "thick", blurBackground: 0, interactiveGlass: false))
        #expect(frosted.frost == "thick" && frosted.blur == 0 && frosted.windowBlur == 0 && !frosted.interactiveGlass)
        #expect(frosted.opacity == 0.25)
    }

    @Test("a tint shows on a terminal at the starting opacity of 0%, not only on a painted canvas")
    func tintShowsOnClearGlass() {
        #expect(TerminalCanvasTint.strength(canvasOpacity: 0) > 0,
                "scaled by opacity, a tint chosen to tell windows apart showed nothing")
        #expect(TerminalCanvasTint.strength(canvasOpacity: 0) == TerminalCanvasTint.strength(canvasOpacity: 1))
    }

    @Test("Settings offers Overrides only with a window to keep the look, and Port Forwarding only for SSH")
    func settingsSections() {
        #expect(TerminalSettingsModalTab.offered(hasSession: true, hasWindowLook: true) == [.terminal, .overrides, .portForwarding])
        #expect(TerminalSettingsModalTab.offered(hasSession: false, hasWindowLook: true) == [.terminal, .overrides],
                "a Mac's local shell: no connection to forward")
        #expect(TerminalSettingsModalTab.offered(hasSession: true, hasWindowLook: false) == [.terminal, .portForwarding])
    }

    @Test("a look that sets nothing, or only out-of-range values, is kept clamped, or not at all")
    func normalized() {
        #expect(TerminalSessionOverride().normalized == nil)
        var wild = TerminalSessionOverride()
        wild.windowOpacity = 3
        wild.blurBackground = -.infinity
        #expect(wild.normalized == TerminalSessionOverride(windowOpacity: 1, blurBackground: 0))
    }

    // MARK: Vision Pro, iPad and iPhone: the workgroup's look

    @Test("set from any tab, the look is the workgroup's: every terminal in it has it, and an empty one is none")
    func workgroupLook() {
        let manager = SessionManager(loadImmediately: false)
        let alpha = server("alpha")
        let one = terminal(alpha, in: manager), two = terminal(alpha, in: manager)
        let group = manager.createWorkgroup(name: "alpha", colorTag: .blue)
        manager.appendSession(one, toWorkgroup: group)
        manager.appendSession(two, toWorkgroup: group)

        manager.setLook(red, forWorkgroup: group)
        #expect(manager.look(ofWorkgroupHolding: one.id) == red)
        #expect(manager.look(ofWorkgroupHolding: two.id) == red, "every tab in the window")

        manager.setLook(TerminalSessionOverride(), forWorkgroup: group)
        #expect(manager.workgroup(for: group)?.look == nil, "reset: back to the settings, nothing kept")
    }

    @Test("a tab moved into another window takes that window's look; moved to a new window it keeps its own")
    func movesTakeTheLook() throws {
        let manager = SessionManager(loadImmediately: false)
        let alpha = server("alpha")
        let a1 = terminal(alpha, in: manager), a2 = terminal(alpha, in: manager), b1 = terminal(alpha, in: manager)
        let left = manager.createWorkgroup(name: "Left", colorTag: .blue, look: red)
        let right = manager.createWorkgroup(name: "Right", colorTag: .blue, look: blue)
        manager.appendSession(a1, toWorkgroup: left)
        manager.appendSession(a2, toWorkgroup: left)
        manager.appendSession(b1, toWorkgroup: right)

        #expect(TerminalTabMoves.move(a1.id, to: right, at: nil, in: manager) == .moved(sourceClosed: false))
        #expect(manager.look(ofWorkgroupHolding: a1.id) == blue, "dragged in, it takes the window's look")
        #expect(manager.workgroup(for: right)?.look == blue && manager.workgroup(for: left)?.look == red,
                "neither window's look changed")

        let created = try #require(TerminalTabMoves.moveToNewWorkgroup(b1.id, in: manager))
        #expect(manager.workgroup(for: created)?.look == blue, "a new window looks like the one it left")
    }

    @Test("a workgroup opened again keeps its look; a new one starts from the look it is given")
    func createdWithLook() {
        let manager = SessionManager(loadImmediately: false)
        let id = UUID()
        manager.createWorkgroup(id: id, name: "Saved", colorTag: .blue, look: red)
        #expect(manager.workgroup(for: id)?.look == red)
        manager.createWorkgroup(id: id, name: "Saved", colorTag: .blue, look: blue)
        #expect(manager.workgroup(for: id)?.look == red, "already open: left as it is")
        let empty = manager.createWorkgroup(name: "Empty", colorTag: .blue, look: TerminalSessionOverride())
        #expect(manager.workgroup(for: empty)?.look == nil)
    }

    @Test("a window's look comes back after a relaunch (W15's list), and a list from before it still reads")
    func reopenedWithLook() async throws {
        try await withDefaults { defaults in
            let alpha = server("alpha")
            let serverManager = ServerManager(loadImmediately: false, defaults: defaults,
                                              passwordStore: ServerPasswordStore(retrieve: { _ in "unused" },
                                                                                 save: { _, _ in }, delete: { _ in }))
            serverManager.servers = [alpha]
            let manager = SessionManager(serverManager: serverManager, loadImmediately: false)
            let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults)
            defer { manager.closeAllSessions() }

            let kept = terminal(alpha, tmux: "glass-1", in: manager)
            let group = manager.createWorkgroup(name: "alpha", colorTag: .blue, look: red)
            manager.appendSession(kept, toWorkgroup: group)
            let records = TerminalWorkgroupsToReopen.records(of: manager.workgroups, session: manager.session(for:),
                                                             isSaved: { _ in true }, leaving: [], shown: nil)
            let record = try #require(records.first)
            #expect(record.look == red, "listed with its look")

            // The next launch: written, read back, reopened under its own id.
            defaults.set(try JSONEncoder().encode(records), forKey: TerminalWorkgroupsToReopen.key)
            let read = try #require(TerminalWorkgroupsToReopen.read(defaults).first)
            manager.closeWorkgroup(group)
            #expect(TerminalWorkgroupOpening.reopen(read, connectsWhenShown: true, sessionManager: manager,
                                                    settingsManager: settings).opened)
            #expect(manager.workgroup(for: group)?.look == red, "back with the look it had")

            var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode([record])) as? [[String: Any]])
            old[0].removeValue(forKey: "look")
            defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: TerminalWorkgroupsToReopen.key)
            #expect(TerminalWorkgroupsToReopen.read(defaults).first?.look == nil, "a list from before W20 still reads")
            #expect(TerminalWorkgroupsToReopen.read(defaults).count == 1)
        }
    }

    // MARK: A saved Workgroup carries the look (D51)

    @Test("a saved Workgroup keeps its look through saving and reading, and never saves an empty one")
    func presetRoundTrip() throws {
        var preset = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        preset.look = red
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset))
        #expect(decoded.look == red)
        #expect(decoded == preset)

        preset.look = TerminalSessionOverride()
        let empty = try json(preset)
        #expect(empty["look"] == nil, "a look that sets nothing is not saved, nor synced")
    }

    @Test("a Workgroup saved before W20 reads with no look; a look that can't be read costs only the look")
    func presetLenient() throws {
        let preset = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        var object = try json(preset)
        #expect(object["look"] == nil)
        let old = try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.look == nil && old.isValidForPersistence)

        let unreadables: [Any] = ["red", ["glassFrost": 7], 42]
        for unreadable in unreadables {
            object["look"] = unreadable
            let decoded = try JSONDecoder().decode(LayoutPreset.self, from: JSONSerialization.data(withJSONObject: object))
            #expect(decoded.look == nil && decoded.id == preset.id && decoded.isValidForPersistence,
                    "the workgroup still reads, and still opens")
        }
    }

    /// An earlier build reads a workgroup with a keyed decoder that ignores keys it doesn't know,
    /// and refuses one whose schema version isn't its own: the look must be one more key, and no
    /// other change, so a Mac or headset not yet updated still reads, opens and syncs it.
    @Test("a Workgroup with a look is the same record to an earlier build, plus one key it ignores")
    func presetReadableByEarlierBuilds() throws {
        var preset = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        let without = try json(preset)
        preset.look = red
        var with = try json(preset)
        #expect(with["look"] != nil)
        #expect(with["schemaVersion"] as? Int == 4, "the schema an earlier build reads")
        with.removeValue(forKey: "look")
        #expect(NSDictionary(dictionary: with).isEqual(to: without), "nothing else changes")
    }

    @Test("a look given on one device reaches the other with the workgroup")
    func lookTravels() async throws {
        let shared = WorkgroupsSyncTests.SharedStore()
        func device() throws -> (SettingsManager, UserDefaults, String) {
            let suite = "TerminalWindowLook.sync.\(UUID())"
            let defaults = try #require(UserDefaults.forTest(suiteName: suite))
            let settings = SettingsManager(loadImmediately: false, settingsDefaults: defaults,
                                           workgroupsSyncService: GlassSettingsSyncService(workgroupsStore: shared.device()))
            return (settings, defaults, suite)
        }
        let (mac, macDefaults, macSuite) = try device()
        let (headset, headsetDefaults, headsetSuite) = try device()
        defer {
            macDefaults.removePersistentDomain(forName: macSuite)
            headsetDefaults.removePersistentDomain(forName: headsetSuite)
        }
        mac.startWorkgroupsSync()
        headset.startWorkgroupsSync()
        try await Task.sleep(for: .milliseconds(50))

        var preset = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        preset.look = red
        mac.upsertLayoutPreset(preset)
        for _ in 0..<200 where !headset.layoutPresets.contains(where: { $0.id == preset.id }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(headset.layoutPresets.first { $0.id == preset.id }?.look == red)
    }

    @Test("saving a window as a Workgroup keeps the window's look, none included; editing keeps the Workgroup's")
    func editorKeepsTheLook() {
        var saved = LayoutPreset(name: "Builds", serverIDs: [UUID()])
        saved.look = red
        let layout = LayoutPreset.WorkspaceLayout(tabs: [.init(label: nil, root: .session(0), focusedSessionIndex: 0)],
                                                  selectedTabIndex: 0)

        let plainWindow = WorkgroupEditorContext(original: nil, name: "Builds", colorTag: .blue,
                                                 sessionIntents: saved.sessionIntents, workspaceLayout: layout)
        #expect(plainWindow.lookToSave(replacing: saved) == nil, "the window had no look: the Workgroup has none")
        let tintedWindow = WorkgroupEditorContext(original: nil, name: "Builds", colorTag: .blue,
                                                  sessionIntents: saved.sessionIntents, workspaceLayout: layout, look: blue)
        #expect(tintedWindow.lookToSave(replacing: saved) == blue)

        #expect(WorkgroupEditorContext.edit(saved).lookToSave(replacing: nil) == red)
        #expect(WorkgroupEditorContext.duplicate(saved).lookToSave(replacing: nil) == red)
        #expect(WorkgroupEditorContext.new(name: "Builds").lookToSave(replacing: saved) == red,
                "made by hand over it: keeps the look of the one it replaces, as it keeps how it opens")
    }

    // MARK: The per-session overrides it replaces

    @Test("per-session overrides left from earlier builds are removed: no later session could use them")
    func leftoverSessionOverridesGo() async throws {
        try await withDefaults { defaults in
            let leftover = [UUID().uuidString: TerminalSessionOverride(glassTint: "#34C759")]
            defaults.set(try JSONEncoder().encode(leftover), forKey: UserDefaultsKeys.sessionOverrides)
            // Loading with sync off: nothing here reaches the real iCloud store.
            defaults.set(false, forKey: UserDefaultsKeys.iCloudSettingsSyncEnabled)
            _ = SettingsManager(settingsDefaults: defaults, sshKeyDefaults: defaults)
            #expect(defaults.object(forKey: UserDefaultsKeys.sessionOverrides) == nil)
        }
    }
}
