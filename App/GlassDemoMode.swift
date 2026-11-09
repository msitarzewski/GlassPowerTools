//
//  GlassDemoMode.swift
//  Glass Power Tools
//
//  Screenshots for the website and the help, taken from the real app on made-up data
//  (`Tools/Screenshots/capture.sh`). DEBUG-only, and only alongside `--ui-testing <uuid>`, whose
//  isolation already keeps a run's storage apart and away from iCloud: nothing here ships, and
//  nothing reaches anyone's library.
//
//  `--demo-open <surface>` opens one surface when the library appears. The visionOS simulator
//  cannot screenshot through XCUITest, so the app opens the surface itself and the capture is taken
//  from outside with `simctl io … screenshot`.
//

#if DEBUG
import SwiftUI
import Charts
import GlassEditor
import GlassTerminal
import GlassLayers
import GlassDatabase
import GlassDesktop
import GlassShell
import GlassConnectionKit
import SQLite3

/// Runs the demo from the library's window; with `--demo-close-connections`, closes that window
/// once the surface has opened, so the picture shows the surface alone, with the room or the
/// desktop behind its glass (the owner, 2026-10-18: "close the connections window so users can see
/// why this was built").
struct GlassDemoModeTask: ViewModifier {
    @Environment(\.dismissWindow) private var dismissWindow
    let run: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content.task {
            await run()
            guard GlassDemoMode.closesConnections else { return }
            // A cancelled task ends here: with `try?` its sleep returned at once and closed the
            // window straight away, before the surface could open.
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            dismissWindow()
        }
    }
}

@MainActor
enum GlassDemoMode {
    private static var didRun = false

    /// The made-up shop's database in the app's Documents. `Tools/Screenshots/shoot.sh` puts the full
    /// one there (`make-demo-db.py`). A UI test cannot reach the app's container, so when the file is
    /// missing a one-table stand-in is made in its place.
    static var shopDatabase: URL {
        let url = URL.documentsDirectory.appending(path: "demo-shop.sqlite")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        var handle: OpaquePointer?
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK {
            sqlite3_exec(handle, "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, total REAL);"
                         + "INSERT INTO orders (customer, total) VALUES ('Ann', 42.5), ('Ben', 17.0);", nil, nil, nil)
        }
        sqlite3_close(handle)
        return url
    }

    /// `--demo-close-connections`, in a demo run.
    static var closesConnections: Bool {
        requestedSurface != nil && ProcessInfo.processInfo.arguments.contains("--demo-close-connections")
    }

    /// The surface asked for, when this is a demo run.
    static var requestedSurface: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--ui-testing"), arguments.indices.contains(flag + 1),
              UUID(uuidString: arguments[flag + 1]) != nil,
              let index = arguments.firstIndex(of: "--demo-open"), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    static func run(editor: GlassEditorRuntime, terminal: GlassTerminalRuntime,
                    database: GlassDatabaseRuntime, desktop: GlassDesktopRuntime,
                    layers: GlassLayerStore, shell: GlassShellModel) async {
        guard !didRun, let surface = requestedSurface else { return }
        didRun = true
        // The theme colour behind content, so a window reads against the simulator's bright room.
        // A setting anyone can choose (Settings ▸ Appearance); the default paints none.
        layers.state.opacity = 0.9
        // `--demo-glass <opacity>,<frost>[,<material>]`: Appearance's two sliders, and its
        // material by name (`thin` is Medium), for checking a window's glass at a given setting (a
        // Vision Pro terminal at Blur 0 is completely clear). The site's pictures use
        // `0.78,0.5,thin`: Opacity 78%, Glass 50%, Medium (the owner, 2026-10-18).
        let arguments = ProcessInfo.processInfo.arguments
        // `--demo-carousel`: a window's overview as the carousel (D99).
        if arguments.contains("--demo-carousel") { GlassTerminalRuntime.demoOverviewAsCarousel() }
        var demoGlass: (opacity: Double, frost: Double)?
        if let index = arguments.firstIndex(of: "--demo-glass"), arguments.indices.contains(index + 1) {
            let parts = arguments[index + 1].split(separator: ",").map(String.init)
            let values = parts.prefix(2).compactMap { Double($0) }
            if values.count == 2 {
                layers.state.opacity = values[0]
                layers.state.frost = values[1]
                demoGlass = (values[0], values[1])
            }
            if parts.count == 3, let material = GlassLayerMaterial(rawValue: parts[2]) {
                layers.state.material = material
            }
        }
        // A desktop has no theme to paint, so its Opacity fades the remote screen instead (W28).
        // The glass given applies to its window; the screen fades too only with `--demo-fade-desktop`.
        let desktopSettings: GlassWindowOverrides = demoGlass.map {
            GlassDesktopRuntime.demoWindowSettings(
                frost: $0.frost,
                opacity: arguments.contains("--demo-fade-desktop") && $0.opacity > 0 ? $0.opacity : nil)
        } ?? GlassWindowOverrides()
        #if os(iOS)
        // `--demo-landscape`: the iPhone turned on its side, for checking the landscape layout
        // without driving the Simulator app's rotate menu.
        if ProcessInfo.processInfo.arguments.contains("--demo-landscape"),
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
        // `--demo-spread`: on an iPhone Duo held like a book, the page in use across both halves
        // (D93, Use Both Pages), for a tool alone.
        if ProcessInfo.processInfo.arguments.contains("--demo-spread") {
            GlassPageFocus.shared.useBothPages(GlassPageFocus.shared.focused)
        }
        #endif
        // `--demo-look <look>` and `--demo-picture <file>` (D84): the terminal window's look — one of
        // This Window's Start From looks (`digitalRain`, `synthwave`, `amberPhosphor`,
        // `greenPhosphor`) — and a picture behind its text; `--demo-look-settings` opens This
        // Window over a `terminal`.
        let demoLook: GlassWindowOverrides = {
            let look = arguments.firstIndex(of: "--demo-look").flatMap {
                arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
            }
            let picture = arguments.firstIndex(of: "--demo-picture").flatMap {
                arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1]) : nil
            }
            return GlassTerminalRuntime.demoLookSettings(look: look, picture: picture)
        }()
        switch surface {
        case "editor", "preview", "preview-only":
            // `preview-only`: the README's preview alone, without the text beside it.
            await openEditor(editor, preview: surface != "editor", previewAlone: surface == "preview-only")
        case "editor-model":
            // A 3D model in the editor's viewer (D78): RealityKit on the Mac, iPhone and iPad, and
            // Apple's Quick Look volume as it opens on Vision Pro. Written here, as the project is.
            await openEditor(editor, preview: false, model: true)
        case "editor-git", "editor-history", "editor-blame":
            // Git in the editor (2026-10-30, the owner: the site shows none of it): the shop as a
            // real repository (GlassDemoGit.swift) — today's changes, its history, or a file's blame.
            await openGitEditor(editor, page: surface)
        case "editor-window", "editor-settings":
            // A window with settings of its own (W23), and This Window open over it.
            await openEditor(editor, preview: false, windowSettings: GlassEditorRuntime.demoWindowSettings,
                             opensSettings: surface == "editor-settings")
        case "terminal":
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8), windowSettings: demoLook,
                                       opensSettings: arguments.contains("--demo-look-settings"))
        case "agent":
            // The Coding Agent look (D84, 2026-10-21): a coding agent at work on the made-up shop,
            // which names itself in its title as Claude Code does, and waits for an answer.
            terminal.requestDemoReplay(name: "alpha", output: Data(agentTranscript.utf8), windowSettings: demoLook)
        case "agent-busy":
            // Coding agents at work in two windows on one machine, as Claude Code is: each writing
            // ten times a second, its title's spinner turning (the owner, 2026-10-25: the gear menu
            // "shows, but using doesn't work" while the terminal is busy). The second stands in front.
            let spinner = ["✶", "✻", "✽", "✻", "✶", "✳"]
            let ticks = spinner.indices.map { step in
                Data("\r\n\u{1B}[2m  ⎿  reading line \(step + 1)\u{1B}[0m".utf8)
            }
            for task in ["Fixing the jobs worker", "Reading the logs"] {
                terminal.requestDemoReplay(name: "alpha", output: Data(agentTranscript.utf8), windowSettings: demoLook,
                                           ticks: ticks, titles: spinner.map { "\($0) \(task)" }, every: .milliseconds(100))
            }
        case "terminal-typing":
            // Keys typed at a prompt, five a second, each echoed in place as a shell echoes it (the
            // owner on the headset, 2026-10-29: "every keypress causes a refresh"), and the line
            // cleared after twenty: what a Vision Pro terminal repaints for one key.
            let typed = Array("ssh deploy@alpha tail -f /var/log/app.log ")
            let ticks = typed.indices.map { index in
                Data((index % 20 == 0 ? "\r\u{1B}[K$ " : "") .appending(String(typed[index])).utf8)
            }
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8), windowSettings: demoLook,
                                       ticks: ticks, every: .milliseconds(200))
        case "terminal-typeahead":
            // Type-ahead's chips (D102, 2026-11-06): three commands run at a shell that marks its prompts, then
            // "git st" typed at the next. What they ran is kept in the demo's own memory, never the device's.
            func ran(_ command: String, _ output: String) -> String {
                "\u{1B}]133;A\u{07}~/shop $ \u{1B}]133;B\u{07}\(command)\r\n\u{1B}]633;E;\(command)\u{07}"
                    + "\u{1B}]133;C\u{07}\(output)\r\n\u{1B}]133;D;0\u{07}"
            }
            let transcript = ran("git status", "On branch main\r\nnothing to commit, working tree clean")
                + ran("git stash list", "stash@{0}: WIP on main: 3f2c1a9 Menu prices")
                + ran("git switch main", "Already on 'main'")
                + "\u{1B}]133;A\u{07}~/shop $ \u{1B}]133;B\u{07}git st"
            terminal.requestDemoReplay(name: "alpha", output: Data(transcript.utf8), windowSettings: demoLook)
        case "terminal-diagram":
            // A Mermaid diagram a coding agent printed as text, with its mark (2026-10-21).
            terminal.requestDemoReplay(name: "alpha", output: Data(diagramTranscript.utf8), windowSettings: demoLook)

        case "btop":
            // The website's terminal (the owner, 2026-10-18: "run btop or something for the
            // terminal examples"): a btop-style monitor of the made-up shop (GlassDemoBtop.swift).
            terminal.requestDemoScreen(name: "alpha", draw: GlassDemoBtop.screen(rows:columns:), windowSettings: demoLook)
        case "workspace":
            // Why the app was built (the owner, 2026-10-18: "close the connections window so users
            // can see why this was built"): a terminal, a database, a remote desktop and the editor,
            // open at once, each in its own window, one at a time so they stack in the same order
            // every run: the editor in front.
            terminal.requestDemoScreen(name: "alpha", draw: GlassDemoBtop.screen(rows:columns:))
            try? await Task.sleep(for: .seconds(3))
            database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop",
                                         showsDiagram: false)
            try? await Task.sleep(for: .seconds(3))
            let renderer = ImageRenderer(content: DemoRemoteScreen())
            renderer.scale = 1
            if let picture = renderer.cgImage {
                await desktop.requestDemoDesktop(name: "bravo", host: "192.0.2.20", picture: picture,
                                                 windowSettings: desktopSettings, opensSettings: false)
            }
            try? await Task.sleep(for: .seconds(3))
            await openEditor(editor, preview: false)
        case "active":
            // Session transfer with tmux (the owner, 2026-10-18: "Don't forget session tranfer with
            // tmux"): Active listing what runs on the machines — open on another device, or
            // detached — to pick up here. Made-up sessions; nothing is behind them.
            // The library behind it is the one in use, so the sidebar's counts are the library's.
            await fillLibrary(shell: shell, terminal: terminal, editor: editor)
            shell.showActiveConnections()
        case "workgroups":
            // Workgroups that come back after a quit (the owner, 2026-10-18): a saved set of
            // terminals on three machines, each keeping its own tmux session.
            while !shell.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(1))
            guard let alpha = terminalService("alpha", in: shell), let build = terminalService("build", in: shell),
                  let nas = terminalService("nas", in: shell) else { return }
            terminal.demoShowWorkgroup(name: "Shop", terminals: [
                (alpha.endpointID, "alpha", alpha.address, "web", "cd ~/shop && docker compose logs -f web", "glass-3"),
                (alpha.endpointID, "alpha", alpha.address, "jobs", "cd ~/shop && docker compose logs -f jobs", "glass-4"),
                (build.endpointID, "build", build.address, "release", "cd ~/shop && make release", "glass-2"),
                (nas.endpointID, "nas", nas.address, "backups", "tail -f /var/log/backup.log", "glass-2"),
            ])
        case "terminal-links", "terminal-paths":
            // 2026-10-15: one long address, or one long log path, on the rows around the screen's
            // middle — the visionOS simulator's test runner holds an element at its middle,
            // whatever point it is given — and less than a screen in all: on a terminal that
            // scrolls, the runner's pinches reached none of its gestures.
            let link = surface == "terminal-links"
                ? "https://example.com/docs/" + String(repeating: "getting-started-", count: 5)
                : "/var/log/shop/" + String(repeating: "jobs-worker-", count: 6) + "out.log"
            let rows = Array(repeating: "", count: 14) + Array(repeating: link, count: 12)
            terminal.requestDemoReplay(name: "alpha", output: Data(rows.joined(separator: "\r\n").utf8))
        case "terminal-tmux", "terminal-tmux-short":
            // 2026-10-15: tmux as SwiftTerm sees it — the alternate screen, the mouse asked for, and
            // a status line redrawn every 0.4 s — over words to select (the owner: "selecting text is
            // still broken wholly in the terminal in visionOS with tmux").
            // `-short`: no word longer than four letters, so a drag from any cell of the word selected,
            // or the space after it, starts within reach of one of its ends (three columns, SwiftTerm's
            // rule). Which letter lies at the terminal's middle changes with the cell size; on
            // 2026-11-05 it became the fourth of six, out of reach of both.
            let phrase = surface == "terminal-tmux-short" ? "drag ends of this text with care " : "select these words on the screen "
            let words = String(repeating: phrase, count: 4)
            let screen = "\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h\u{1B}[H\u{1B}[2J"
                + Array(repeating: words, count: 60).joined(separator: "\r\n")
            let status = "\u{1B}7\u{1B}[999;1H\u{1B}[7m[0] 0:zsh*  \u{1B}[0m\u{1B}8"
            terminal.requestDemoReplay(name: "alpha", output: Data(screen.utf8), ticks: [Data(status.utf8)])
        case "terminal-window", "terminal-settings":
            // A window with settings of its own (W22), and This Window open over it.
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8),
                                       windowSettings: GlassTerminalRuntime.demoWindowSettings,
                                       opensSettings: surface == "terminal-settings")
        case "terminal-path":
            // 2026-10-22: a path everywhere on the screen, for Quick Look on a held path: the
            // simulator's runner holds the terminal's middle, whatever point is asked for. The demo
            // is connected to nothing, so its preview says it can't read the file.
            let row = Array(repeating: "/home/ann/shop/README.md", count: 8).joined(separator: " ")
            terminal.requestDemoReplay(name: "alpha", output: Data((Array(repeating: row, count: 44).joined(separator: "\r\n")).utf8))
        case "terminal-move":
            // Two windows of one terminal each (W26): the tools menu's Move Tab To lists the other,
            // and either title drags into the other window.
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8))
            terminal.requestDemoReplay(name: "bravo", output: Data("ann@bravo:~$ ".utf8))
        case "library-history":
            await fillLibrary(shell: shell, terminal: terminal, editor: editor)
        case "terminal-ring", "terminal-agents", "terminal-agents-grid":
            // 2026-10-15: ten terminals in one window, for its orb's ring (`--demo-session-orb`, and
            // `--demo-orb-names` to see where every name sits). `terminal-agents` (2026-10-27): five
            // named as coding agents name their terminals, long enough that an open name crosses the
            // ring, as the owner's did in the dock, each writing ten times a second as one at work
            // does (the owner, that day: "the hyper refresh is back and the gear no longer works");
            // `terminal-agents-grid` in the grid, where Auto-focus on activity brings one forward.
            if surface.hasPrefix("terminal-agents") {
                let ticks = (1...6).map { Data("\r\n\u{1B}[2m  ⎿  reading line \($0)\u{1B}[0m".utf8) }
                terminal.requestDemoTabs(names: ["✳ Storefront checkout redesign", "✳ Fix the flaky login tests",
                                                 "✳ Migrate orders to Postgres", "✳ Draft the release notes",
                                                 "✳ Review the search indexing"],
                                         output: Data(agentTranscript.utf8), grid: surface == "terminal-agents-grid",
                                         ticks: ticks, every: .milliseconds(100))
            } else {
                terminal.requestDemoTabs(names: ["build", "logs", "api", "web", "db", "cache", "jobs", "deploy", "docs", "tests"],
                                         output: Data(terminalTranscript.utf8), grid: false)
            }
        case "terminal-carousel":
            // The site's carousel (2026-11-03, the owner: "The new coverflow view for terminals too!"): a
            // window of five tabs, the first a btop-style monitor on alpha and four coding agents at work on
            // the shop, each with its mark. Off the Mac it opens in the window's overview (with
            // `--demo-carousel`, the carousel, and `--demo-visit-tabs`, each tab shown first so it has a
            // picture); on the Mac site_shots.sh shows each tab and opens the overview itself.
            terminal.requestDemoTabs(names: ["alpha", "✳ Storefront checkout redesign", "✳ Fix the jobs worker",
                                             "✳ Migrate orders to Postgres", "✳ Draft the release notes"],
                                     output: Data(agentTranscript.utf8), grid: true, windowSettings: demoLook,
                                     firstDraw: GlassDemoBtop.screen(rows:columns:))
        case "terminal-tabs", "terminal-grid":
            // W31: one window with two terminals as its tabs, shown in tabs and in the grid, for
            // checking that one bottom bar shows. The shell reports its folder (OSC 7) as shells
            // do, a `file://` URL, so Open Folder Here opens it as on a real shell. (It reported a
            // bare path, which no shell sends, and so hid that the bar read only that: 2026-11-09.)
            terminal.requestDemoTabs(names: ["alpha", "bravo"],
                                     output: Data(("\u{1B}]7;file://alpha/home/ann/shop\u{07}" + terminalTranscript).utf8),
                                     grid: surface == "terminal-grid", windowSettings: demoLook)
        case "connections-host":
            // The Connections window at its first size with a machine's details showing (W29).
            while !shell.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            if let alpha = shell.hosts.first(where: { $0.displayName == "alpha" }) { shell.showHost(alpha.id) }
        case "dock":
            // The orb dock (D88; 2026-10-30, the owner: "we don't have screen shots of the amazing
            // dock on the website!"): coding agents at work, a monitor on the build machine, the
            // shop's database and the editor, each gathered into the dock a few seconds after it
            // opens, then the shop's monitor open beside it. `--demo-orb-name <title>` shows one name.
            #if os(visionOS)
            GlassUITestRun.settingsDefaults.set(true, forKey: GlassOrbDock.settingKey)
            GlassOrbDockModel.demoOpensBelowConnections = arguments.contains("--demo-dock-below")
            GlassSessionOrbDemo.shrinksNext = true
            let ticks = (1...6).map { Data("\r\n\u{1B}[2m  ⎿  reading line \($0)\u{1B}[0m".utf8) }
            terminal.requestDemoTabs(names: ["✳ Storefront checkout redesign", "✳ Fix the flaky login tests",
                                             "✳ Migrate orders to Postgres"],
                                     output: Data(agentTranscript.utf8), grid: false,
                                     ticks: ticks, every: .milliseconds(100))
            try? await Task.sleep(for: .seconds(2))
            terminal.requestDemoScreen(name: "build", draw: GlassDemoBtop.screen(rows:columns:), windowSettings: demoLook)
            try? await Task.sleep(for: .seconds(2))
            database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop", showsDiagram: false)
            try? await Task.sleep(for: .seconds(2))
            await openEditor(editor, preview: false)
            try? await Task.sleep(for: .seconds(12))
            GlassSessionOrbDemo.shrinksNext = false
            // `--demo-dock-alone`: the dock by itself. Otherwise a terminal with its tabs, back above the
            // dock as a window from the dock comes (the owner, 2026-10-31: "the terminal above with tabs
            // open and the full dock below").
            guard !arguments.contains("--demo-dock-alone") else { return }
            GlassOrbDockModel.shared.demoNextWindowByDock()
            terminal.requestDemoTabs(names: ["shop", "jobs", "release", "backups"], output: Data(terminalTranscript.utf8),
                                     grid: false, windowSettings: demoLook, firstDraw: GlassDemoBtop.screen(rows:columns:))
            #endif
        case "orb", "orb-looked-at":
            // Connections shrunk into its orb by the real idle path (W29): two terminals open, so
            // it is not the only window and Active counts two. Needs `--demo-idle-seconds <n>`;
            // `orb-looked-at` shows the effect the system draws while the orb is looked at.
            #if os(visionOS)
            GlassConnectionsOrb.demoShowsLookedAt = surface == "orb-looked-at"
            #endif
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8))
            terminal.requestDemoReplay(name: "bravo", output: Data("ann@bravo:~$ ".utf8))
        case "orb-later", "orb-later-desktop":
            // For `GlassConnectionsOrbUITests`: one other window after 20 s, so the test uses
            // Connections before it opens in front — a terminal, whose Connections control is a
            // way back, or a desktop, whose ⚡ is. One each: a second would stand in front of the
            // first, and the runner's taps reach only the window in front.
            try? await Task.sleep(for: .seconds(20))
            if surface == "orb-later" {
                terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8))
            } else {
                let renderer = ImageRenderer(content: DemoRemoteScreen())
                renderer.scale = 1
                guard let picture = renderer.cgImage else { return }
                await desktop.requestDemoDesktop(name: "bravo", host: "192.0.2.20", picture: picture,
                                                 windowSettings: GlassWindowOverrides(), opensSettings: false)
            }
        case "files":
            // The window and its header; with nothing connected, the list says so.
            terminal.requestDemoFiles(name: "alpha", path: "/home/ann/shop")
        #if os(iOS)
        case "pages", "pages-desktop", "pages-editor":
            // Two services side by side on an iPhone Duo held like a book (D93): the monitor in one
            // page, then in the other the shop's database, a remote desktop, or the shop's code.
            terminal.requestDemoScreen(name: "alpha", draw: GlassDemoBtop.screen(rows:columns:), windowSettings: demoLook)
            try? await Task.sleep(for: .seconds(3))
            GlassPageFocus.shared.focusOtherPage()
            try? await Task.sleep(for: .milliseconds(500))
            switch surface {
            case "pages-desktop":
                let renderer = ImageRenderer(content: DemoRemoteScreen())
                renderer.scale = 1
                guard let picture = renderer.cgImage else { return }
                await desktop.requestDemoDesktop(name: "bravo", host: "192.0.2.20", picture: picture,
                                                 windowSettings: desktopSettings, opensSettings: false)
            case "pages-editor":
                await openEditor(editor, preview: false)
            default:
                database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop", showsDiagram: false)
            }
        #endif
        case "database", "diagram":
            // Put there by Tools/Screenshots/shoot.sh, from make-demo-db.py.
            database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop",
                                         showsDiagram: surface == "diagram")
        case "database-sql":
            // SQL from a terminal (2026-10-20; pictured 2026-10-30): a query a coding agent printed in
            // alpha's terminal, brought to the query editor as Open in SQL Editor brings it, the
            // orders table beside it. The terminal opens first, so the database stands in front.
            terminal.requestDemoReplay(name: "alpha", output: Data(sqlTranscript.utf8), windowSettings: demoLook)
            try? await Task.sleep(for: .seconds(3))
            database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop", start: .sql(demoSQL))
        case "database-server", "database-main":
            // W32: the server's overview, or the `main` database's, for their titles and tiles.
            database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop",
                                         start: surface == "database-server" ? .server : .database)
        case "editor-project":
            // W32: the shop's repository open with no file in front, for its overview page.
            let root = URL.documentsDirectory.appending(path: "shop", directoryHint: .isDirectory)
            for (path, text) in projectFiles {
                let url = root.appending(path: path)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? Data(text.utf8).write(to: url)
            }
            if let window = editor.openProject(root) { editor.present(window) }
        case "database-window", "database-settings":
            // A database window with settings of its own (W24), and This Window open over it.
            database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop",
                                         windowSettings: GlassDatabaseRuntime.demoWindowSettings,
                                         opensSettings: surface == "database-settings")
        case "desktop", "desktop-window", "desktop-settings":
            let renderer = ImageRenderer(content: DemoRemoteScreen())
            renderer.scale = 1
            guard let picture = renderer.cgImage else { return }
            // `desktop-window`: a window with settings of its own (W25); `desktop-settings`: and
            // Desktop Settings ▸ This Window open over it. `desktop` with `--demo-glass`: the
            // window's glass is the frost given (a desktop's glass is its own Background Frost,
            // not Appearance's), and with `--demo-fade-desktop` an opacity above 0 fades the remote
            // screen (`desktopSettings`, above).
            let windowSettings = surface == "desktop" ? desktopSettings : GlassDesktopRuntime.demoWindowSettings
            // With `--demo-desktop-resizes`, the made-up server changes its size to the window's as an
            // RDP server does (the iPhone Duo's top half, 2026-11-03); otherwise it stays 1920 × 1080,
            // as the site's Mac and Vision Pro pictures and their words have it.
            var redraw: (@MainActor (DesktopSize) -> CGImage?)?
            if ProcessInfo.processInfo.arguments.contains("--demo-desktop-resizes") {
                redraw = { size in DemoRemoteScreen.picture(width: size.width, height: size.height) }
            }
            await desktop.requestDemoDesktop(
                name: "bravo", host: "192.0.2.20", picture: picture,
                windowSettings: windowSettings,
                opensSettings: surface == "desktop-settings", redraw: redraw)
        case "all-windows":
            // All Windows (2026-10-14): a window of three terminals as tabs, the first running
            // the btop-style monitor, the shop's database, a desktop and an editor, then All Windows
            // over them, a card per tab. On the Mac, Tools/Screenshots/site_shots.sh presses Show
            // All Windows itself (2026-10-31, the owner: the Mac's was on the site nowhere).
            terminal.requestDemoTabs(names: ["alpha", "build", "nas"],
                                     output: Data(terminalTranscript.utf8), grid: false, windowSettings: demoLook,
                                     firstDraw: GlassDemoBtop.screen(rows:columns:))
            try? await Task.sleep(for: .seconds(2))
            database.requestDemoDatabase(file: GlassDemoMode.shopDatabase, name: "shop", showsDiagram: false)
            try? await Task.sleep(for: .seconds(2))
            let renderer = ImageRenderer(content: DemoRemoteScreen())
            renderer.scale = 1
            if let picture = renderer.cgImage {
                await desktop.requestDemoDesktop(name: "bravo", host: "192.0.2.20", picture: picture,
                                                 windowSettings: GlassWindowOverrides(), opensSettings: false)
            }
            await openEditor(editor, preview: false)
            try? await Task.sleep(for: .seconds(3))
            #if os(visionOS)
            GlassWindowOpener.shared.perform { GlassShowAllWindows.presentOverview(openWindow: $0) }
            #elseif os(iOS)
            GlassShowAllWindows.presentOverview()
            #endif
        case "desktop-disconnected":
            await desktop.requestDemoDisconnectedDesktop(name: "bravo", host: "192.0.2.20")
        case "desktop-displays", "desktop-quality":
            // W30: a host with two displays, a window each, on one connection; `desktop-quality`
            // opens Desktop Settings ▸ Connection (Quality and the readout) over the desktop's window.
            let renderer = ImageRenderer(content: DemoRemoteScreen())
            renderer.scale = 1
            guard let picture = renderer.cgImage else { return }
            await desktop.requestDemoDisplays(name: "bravo", host: "192.0.2.20", mainDisplay: picture,
                                              opensSettings: surface == "desktop-quality")
        default:
            break
        }
    }

    /// The made-up machine `name`'s Terminal service, and its address.
    private static func terminalService(_ name: String, in shell: GlassShellModel) -> (endpointID: EndpointID, address: String)? {
        guard let host = shell.hosts.first(where: { $0.displayName == name }),
              let ssh = host.services.first(where: { $0.kind == .ssh }) else { return nil }
        return (ssh.endpointID, host.address ?? "192.0.2.1")
    }

    /// The library as one in use looks (the owner, 2026-10-30, of a library picture half
    /// empty: "There's a balance that needs to be had between showing the product and
    /// chaotic display"): a month of invented connections and minutes in use behind the
    /// overview's chart and Most used, the machines last connected in Recent, favourites,
    /// tmux sessions in Active, and saved workgroups, keys and projects in the sidebar.
    /// The collections come with the machines (`#` in `--ui-testing-seed-hosts`).
    private static func fillLibrary(shell: GlassShellModel, terminal: GlassTerminalRuntime,
                                    editor: GlassEditorRuntime) async {
        while !shell.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }
        var connections: [(host: String, daysAgo: Int, kind: HostServiceKind)] = []
        var minutes: [(host: String, daysAgo: Int, kind: HostServiceKind, minutes: Int)] = []
        for day in 0..<30 {
            // Lighter at the weekend, and no two weekdays alike.
            let weekend = day % 7 >= 5, vary = (day * 37) % 7
            connections.append(("alpha", day, .ssh))
            minutes.append(("alpha", day, .ssh, weekend ? 40 : 150 + vary * 30))
            if !weekend && day % 2 == 0 {
                connections.append(("alpha", day, .database))
                minutes.append(("alpha", day, .database, 20 + vary * 5))
            }
            if day % 2 == 1 {
                connections.append(("build", day, .ssh))
                minutes.append(("build", day, .ssh, 30 + vary * 12))
            }
            if day % 3 == 0 {
                connections.append(("db", day, .database))
                minutes.append(("db", day, .database, 25 + vary * 8))
            }
            if day % 3 == 1 {
                connections.append(("staging", day, .ssh))
                minutes.append(("staging", day, .ssh, 20 + vary * 6))
            }
            if day % 4 == 2 {
                connections.append(("bravo", day, .rdp))
                minutes.append(("bravo", day, .rdp, 45 + vary * 15))
            }
            if day % 6 == 3 { connections.append(("win", day, .rdp)); minutes.append(("win", day, .rdp, 30)) }
            if day % 7 == 6 { connections.append(("nas", day, .ssh)); minutes.append(("nas", day, .ssh, 10)) }
            if day % 9 == 4 { connections.append(("pi", day, .ssh)); minutes.append(("pi", day, .ssh, 8)) }
        }
        shell.demoRecordConnections(connections)
        shell.demoRecordMinutes(minutes)
        shell.demoMarkFavorites(["alpha", "build", "db"])
        // The footer as on a device signed out of iCloud, which the screenshot VM is.
        shell.demoSignedOutOfICloud()
        // Two more devices, as iCloud would bring them (D81): the overview's All Devices and
        // its device choice. Invented names, as the rest of the demo's.
        shell.demoOtherDevices([("Studio Mac", [("alpha", .ssh, 3, 120), ("build", .ssh, 2, 40)]),
                                ("Vision Pro (Lab)", [("bravo", .rdp, 2, 60), ("alpha", .database, 1, 20)])])
        shell.demoRunningSessions(runningSessions(in: shell))
        if let alpha = terminalService("alpha", in: shell), let build = terminalService("build", in: shell),
           let nas = terminalService("nas", in: shell), let staging = terminalService("staging", in: shell),
           let db = terminalService("db", in: shell) {
            terminal.demoLibraryExtras(workgroups: [
                ("Shop", [(alpha.endpointID, "alpha", alpha.address, "web", "cd ~/shop && docker compose logs -f web", "glass-3"),
                          (build.endpointID, "build", build.address, "release", "cd ~/shop && make release", "glass-2"),
                          (nas.endpointID, "nas", nas.address, "backups", "tail -f /var/log/backup.log", "glass-2")]),
                ("Staging", [(staging.endpointID, "staging", staging.address, "app", "cd ~/shop && make serve", "glass-1"),
                             (db.endpointID, "db", db.address, "psql", "psql shop", "glass-1")]),
            ], keys: [("ann@studio", false), ("deploy", false), ("Secure Enclave", true)])
        }
        // Folders on this device, as Open Folder keeps them.
        for name in ["shop", "docs", "infra", "website"] {
            let folder = URL.documentsDirectory.appending(path: name, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            editor.remember(.local(folder))
        }
    }

    /// tmux sessions running on the machines, open on another device or detached, as Active lists
    /// them when the machines answer. Made up; nothing is behind them.
    private static func runningSessions(in shell: GlassShellModel) -> [GlassRunningSession] {
        var sessions: [GlassRunningSession] = []
        if let alpha = terminalService("alpha", in: shell)?.endpointID {
            sessions += GlassTerminalCapability.demoRunningSessions(on: alpha, [
                ("glass-1", nil, "shop", "shop", "main", 1, 1),
                ("glass-2", "jobs", "shop", "shop", "main", 0, 35),
            ])
        }
        if let build = terminalService("build", in: shell)?.endpointID {
            sessions += GlassTerminalCapability.demoRunningSessions(on: build, [
                ("glass-1", "release", "shop", "shop", "release/2.15", 1, 3),
            ])
        }
        if let nas = terminalService("nas", in: shell)?.endpointID {
            sessions += GlassTerminalCapability.demoRunningSessions(on: nas, [
                ("glass-1", nil, "backups", nil, nil, 0, 190),
            ])
        }
        return sessions
    }

    /// A believable few minutes in a shell on `alpha`: invented repository, invented containers.
    static let terminalTranscript: String = {
        let e = "\u{1B}["
        let prompt = "\(e)1;32mann@alpha\(e)0m:\(e)1;34m~/shop\(e)0m$ "
        let lines = [
            prompt + "git log --oneline --graph -6",
            "* \(e)33m3f2a9c1\(e)0m \(e)1;36m(HEAD -> \(e)1;32mmain\(e)1;36m, \(e)1;31morigin/main\(e)1;36m)\(e)0m Checkout remembers the last shipping address",
            "* \(e)33m8b41e07\(e)0m Orders: page the admin list by 50",
            "*   \(e)33mc2d9a54\(e)0m Merge branch 'stock-alerts'",
            "|\\  ",
            "| * \(e)33m71e0f3b\(e)0m Alert when stock falls under ten",
            "* \(e)33m0a9d2c6\(e)0m Products: SKU is unique per catalog",
            prompt + "docker compose ps",
            "NAME          IMAGE              STATUS                  PORTS",
            "shop-web-1    shop-web:2.14      \(e)32mUp 3 days (healthy)\(e)0m     0.0.0.0:8080->8080/tcp",
            "shop-db-1     postgres:18        \(e)32mUp 3 days (healthy)\(e)0m     5432/tcp",
            "shop-cache-1  valkey:8           \(e)32mUp 3 days\(e)0m               6379/tcp",
            "shop-jobs-1   shop-jobs:2.14     \(e)33mRestarting (1) 4s ago\(e)0m",
            prompt + "docker compose logs --tail 4 jobs",
            "\(e)36mshop-jobs-1\(e)0m  | 09:41:07 INFO  worker ready, queue=default",
            "\(e)36mshop-jobs-1\(e)0m  | 09:41:07 INFO  picked job 88213 (send-receipt)",
            "\(e)36mshop-jobs-1\(e)0m  | 09:41:08 \(e)31mERROR\(e)0m smtp: connection refused (mail.example.com:587)",
            "\(e)36mshop-jobs-1\(e)0m  | 09:41:08 INFO  retrying in 5s",
            prompt + "uptime",
            " 09:41:12 up 23 days,  4:02,  1 user,  load average: 0.42, 0.37, 0.31",
            prompt,
        ]
        return lines.joined(separator: "\r\n")
    }()

    /// A coding agent finding why the shop's jobs worker restarts (`terminalTranscript`'s error),
    /// and waiting for an answer. It sets the title Claude Code sets, which is how the app knows
    /// an agent runs where no program name says so.
    static let agentTranscript: String = {
        let e = "\u{1B}["
        let dot = "\(e)38;5;174m⏺\(e)0m"
        let dim = "\(e)2m"
        let lines = [
            "\u{1B}]0;✳ Claude Code\u{07}",
            "\(e)2m>\(e)0m The jobs worker keeps restarting. Find out why.",
            "",
            "\(dot) Reading the worker's last log lines.",
            "",
            "\(dot) \(e)1mBash\(e)0m(docker compose logs --tail 4 jobs)",
            "  \(dim)⎿\(e)0m  shop-jobs-1 | 09:41:08 \(e)31mERROR\(e)0m smtp: connection refused (mail.example.com:587)",
            "",
            "\(dot) The worker can't reach mail.example.com on port 587, so every send-receipt",
            "  job fails and the container restarts. SMTP_HOST in .env still names the old relay.",
            "",
            "\(dot) \(e)1mUpdate\(e)0m(.env)",
            "  \(dim)⎿\(e)0m  \(e)31m- SMTP_HOST=mail.example.com\(e)0m",
            "     \(e)32m+ SMTP_HOST=relay.example.com\(e)0m",
            "",
            "  Restart the jobs worker so it picks this up?",
            "",
            "\(dim)────────────────────────────────────────────────────────────────────\(e)0m",
            "> ",
            "\(dim)────────────────────────────────────────────────────────────────────\(e)0m",
            "  \(dim)? for shortcuts\(e)0m",
        ]
        return lines.joined(separator: "\r\n")
    }()

    /// A coding agent explaining the made-up shop's receipts with a Mermaid diagram it could not draw
    /// in the terminal, printed as Claude Code prints one (2026-10-21, the owner's paste).
    static let diagramTranscript: String = {
        let e = "\u{1B}["
        let dot = "\(e)38;5;174m⏺\(e)0m"
        let dim = "\(e)2m"
        let lines = [
            "\u{1B}]0;✳ Claude Code\u{07}",
            "\(e)2m>\(e)0m How does a receipt get from the shop to the customer?",
            "",
            "\(dot) This Mermaid diagram uses features the terminal renderer doesn't support.",
            "  flowchart LR",
            "      A[Order placed<br/>in the shop] --> B[Jobs worker]",
            "      B -->|send-receipt| C[Mail relay]",
            "      C --> D[Customer's inbox]",
            "",
            "  The worker sends every receipt through the relay named in SMTP_HOST.",
            "",
            "\(dim)────────────────────────────────────────────────────────────────────\(e)0m",
            "> ",
            "\(dim)────────────────────────────────────────────────────────────────────\(e)0m",
        ]
        return lines.joined(separator: "\r\n")
    }()

    /// A coding agent answering with `demoSQL`, printed as a code block, for `database-sql`.
    static let sqlTranscript: String = {
        let e = "\u{1B}["
        let dot = "\(e)38;5;174m⏺\(e)0m"
        let dim = "\(e)2m"
        let query = demoSQL.split(separator: "\n").map { "  \(e)36m\($0)\(e)0m" }
        let lines = [
            "\u{1B}]0;✳ Claude Code\u{07}",
            "\(e)2m>\(e)0m Who are the shop's best customers?",
            "",
            "\(dot) This ranks customers by what their delivered orders came to:",
            "",
        ] + query + [
            "",
            "  Run it on the shop database to see the list.",
            "",
            "\(dim)────────────────────────────────────────────────────────────────────\(e)0m",
            "> ",
            "\(dim)────────────────────────────────────────────────────────────────────\(e)0m",
        ]
        // The cursor back in the answer box, after its "> ".
        return lines.joined(separator: "\r\n") + "\(e)A\r\(e)2C"
    }()

    /// The invented shop's repository, written into Documents and opened: several files in tabs,
    /// the Swift one in front; for `preview`, the README with its rendered preview beside it. With
    /// `windowSettings`, the window keeps them as its own (W23); with `opensSettings`, Editor
    /// Settings ▸ This Window opens over it.
    private static func openEditor(_ editor: GlassEditorRuntime, preview: Bool,
                                   windowSettings: GlassWindowOverrides = GlassWindowOverrides(),
                                   opensSettings: Bool = false, model: Bool = false,
                                   previewAlone: Bool = false) async {
        let root = URL.documentsDirectory.appending(path: "shop", directoryHint: .isDirectory)
        // The shop as its last commit has it (GlassDemoGit.swift), so the file list is a project's,
        // with the files the pictures show over it; afresh, so no repository is left from `editor-git`.
        #if os(macOS) || targetEnvironment(simulator)
        try? FileManager.default.removeItem(at: root)
        let files = GlassDemoShopFiles.first + GlassDemoShopFiles.products + GlassDemoShopFiles.stockAlerts
            + GlassDemoShopFiles.orders + GlassDemoShopFiles.lastAddress + projectFiles
        #else
        let files = projectFiles
        #endif
        do {
            for (path, text) in files {
                let url = root.appending(path: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
        } catch { return }
        guard let window = editor.openProject(root) else { return }
        let workspace = editor.workspace(for: window)
        if !windowSettings.isEmpty { workspace.setWindowSettings(windowSettings) }
        workspace.demoOpensSettings = opensSettings
        let order = preview
            ? ["compose.yaml", "Sources/Checkout/ShippingAddress.swift", "README.md"]
            : ["compose.yaml", "README.md", "Sources/Checkout/ShippingAddress.swift"]
        var last: GlassEditorDocument?
        for path in order { last = await workspace.open(root.appending(path: path)) }
        if model {
            let scene = root.appending(path: "Scene.usda")
            try? Data(demoModel.utf8).write(to: scene)
            _ = await workspace.open(scene)
            // A USDZ put beside the project by hand (`simctl get_app_container`) opens too, last.
            let others = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for file in others where file.pathExtension.lowercased() == "usdz" { _ = await workspace.open(file) }
        }
        if preview, let last { workspace.previewModes[last.id] = previewAlone ? .previewOnly : .beside }
        await openSourcesFolders(in: workspace)
        editor.present(window)
    }

    /// `Sources` and the folders in it opened in the file list (2026-10-30, the owner, of a picture
    /// with four rows over an empty column: "There's a balance that needs to be had between showing
    /// the product and chaotic display"). A folder's children load as it opens, so each is waited for.
    private static func openSourcesFolders(in workspace: GlassEditorWorkspace) async {
        func folder(_ name: String, in parent: GlassEditorProjectNode?) async -> GlassEditorProjectNode? {
            for _ in 0..<50 {
                if let found = parent?.children?.first(where: { $0.isDirectory && $0.name == name }) { return found }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return nil
        }
        guard let sources = await folder("Sources", in: workspace.projectRoots.values.first) else { return }
        workspace.setExpanded(true, for: sources.id)
        for _ in 0..<50 where sources.children == nil { try? await Task.sleep(for: .milliseconds(100)) }
        for child in sources.children ?? [] where child.isDirectory { workspace.setExpanded(true, for: child.id) }
    }

    /// The shop as a repository with a history, open in the editor at `page`: `editor-git` the
    /// Changes tab — the relay staged, the address checks and the README changed, a file new and
    /// one gone — `editor-history` Source Control's History, `editor-blame` a file's Blame. Off the
    /// Mac, the simulator's app runs the Mac's `git` (`GlassEditorLocalFileAccess.demoGitRunner`).
    private static func openGitEditor(_ editor: GlassEditorRuntime, page: String) async {
        #if os(macOS) || targetEnvironment(simulator)
        #if !os(macOS)
        GlassEditorLocalFileAccess.demoGitRunner = GlassDemoGitRunner()
        #endif
        let root = URL.documentsDirectory.appending(path: "shop", directoryHint: .isDirectory)
        guard await GlassDemoShop.makeRepository(at: root), let window = editor.openProject(root) else { return }
        let workspace = editor.workspace(for: window)
        let file = root.appending(path: "Sources/Checkout/ShippingAddress.swift")
        _ = await workspace.open(file)
        // The repository reads a moment after the project opens.
        for _ in 0..<100 {
            if let id = workspace.projects.first?.id, workspace.repositories[id]?.state == .ready { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        switch page {
        case "editor-history": workspace.showSourceControl(.history)
        case "editor-blame": workspace.showGit(.blame(file.path), of: file.path)
        default: workspace.showChanges()
        }
        await openSourcesFolders(in: workspace)
        editor.present(window)
        #endif
    }

    /// The query in `database-sql`: the shop's best customers by delivered orders.
    static let demoSQL = """
    SELECT c.name, c.city, COUNT(o.id) AS orders,
           SUM(o.total_cents) / 100.0 AS spent
    FROM orders o
    JOIN customers c ON c.id = o.customer_id
    WHERE o.status = 'delivered'
    GROUP BY c.id
    ORDER BY spent DESC
    LIMIT 25;
    """

    /// A blue box and an orange ball, in USD's text form, for `editor-model`.
    private static let demoModel = """
    #usda 1.0
    (
        defaultPrim = "Scene"
        metersPerUnit = 1
        upAxis = "Y"
    )

    def Xform "Scene"
    {
        def Cube "Box" (
            prepend apiSchemas = ["MaterialBindingAPI"]
        )
        {
            double size = 0.2
            double3 xformOp:translate = (-0.15, 0.1, 0)
            uniform token[] xformOpOrder = ["xformOp:translate"]
            rel material:binding = </Scene/Materials/Blue>
        }

        def Sphere "Ball" (
            prepend apiSchemas = ["MaterialBindingAPI"]
        )
        {
            double radius = 0.1
            double3 xformOp:translate = (0.15, 0.1, 0)
            uniform token[] xformOpOrder = ["xformOp:translate"]
            rel material:binding = </Scene/Materials/Orange>
        }

        def Scope "Materials"
        {
            def Material "Blue"
            {
                token outputs:surface.connect = </Scene/Materials/Blue/Surface.outputs:surface>
                def Shader "Surface"
                {
                    uniform token info:id = "UsdPreviewSurface"
                    color3f inputs:diffuseColor = (0.15, 0.4, 0.95)
                    float inputs:roughness = 0.35
                    token outputs:surface
                }
            }

            def Material "Orange"
            {
                token outputs:surface.connect = </Scene/Materials/Orange/Surface.outputs:surface>
                def Shader "Surface"
                {
                    uniform token info:id = "UsdPreviewSurface"
                    color3f inputs:diffuseColor = (0.95, 0.5, 0.1)
                    float inputs:roughness = 0.25
                    token outputs:surface
                }
            }
        }
    }
    """

    private static let projectFiles: [(String, String)] = [
        ("README.md", """
        # shop

        The storefront, its admin and the job runner, deployed with Compose.

        | Service | Image | Port |
        |---|---|---|
        | web | shop-web | 8080 |
        | db | postgres:18 | 5432 |
        | jobs | shop-jobs | — |

        ```mermaid
        graph LR
          Browser --> web
          web --> db
          web --> cache
          jobs --> db
          jobs --> mail[mail.example.com]
        ```

        ## Deploying

        1. Tag the release: `git tag v2.14.1`
        2. Run `./deploy.sh alpha`
        3. Watch `docker compose logs -f jobs` until the queue drains.

        > [!NOTE]
        > Receipts retry for an hour when the mail server is down.

        """),
        ("Sources/Checkout/ShippingAddress.swift", """
        import Foundation

        /// The address an order ships to. Checkout offers the customer's last one first.
        struct ShippingAddress: Codable, Hashable, Sendable {
            var name: String
            var street: String
            var city: String
            var postalCode: String
            var country: String

            /// Blank fields a courier would refuse, in the order the form shows them.
            var missingFields: [String] {
                let fields = [("name", name), ("street", street),
                              ("city", city), ("postal code", postalCode)]
                return fields
                    .filter { $0.1.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map(\\.0)
            }
        }

        extension CheckoutSession {
            /// The address used last time, if the customer has ordered before.
            func lastAddress(of customer: Customer.ID) async throws -> ShippingAddress? {
                let recent = try await orders.latest(for: customer, limit: 1)
                return recent.first?.shippingAddress
            }

            mutating func ship(to address: ShippingAddress) throws {
                guard address.missingFields.isEmpty else {
                    throw CheckoutError.incompleteAddress(address.missingFields)
                }
                self.address = address
                step = .payment
            }
        }

        """),
        ("compose.yaml", """
        services:
          web:
            image: shop-web:2.14
            ports: ["8080:8080"]
            depends_on: [db, cache]
          db:
            image: postgres:18
            volumes: [db:/var/lib/postgresql/data]
          cache:
            image: valkey:8
          jobs:
            image: shop-jobs:2.14
            environment:
              SMTP_HOST: mail.example.com

        volumes:
          db:

        """),
        ("deploy.sh", """
        #!/bin/sh
        set -eu
        ssh "$1" 'cd shop && docker compose pull && docker compose up -d'

        """),
    ]
}

/// The remote screen in the desktop shot: an invented Linux desktop — wallpaper, a top bar, a
/// monitoring window and a file list. Drawn here so every pixel is ours; no product's look.
private struct DemoRemoteScreen: View {
    /// The screen's size: 1920 × 1080, or a resized desktop's shape at the same width, its windows
    /// as they were and more of the wallpaper above and below them.
    var size = CGSize(width: 1920, height: 1080)

    /// The screen drawn `width` × `height` pixels: a desktop resized to that shape (`--demo-desktop-resizes`).
    @MainActor static func picture(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let renderer = ImageRenderer(content: DemoRemoteScreen(size: CGSize(width: 1920, height: 1920 * Double(height) / Double(width))))
        renderer.scale = Double(width) / 1920
        return renderer.cgImage
    }

    private struct Sample: Identifiable { let id = UUID(); let minute: Int; let host: String; let load: Double }
    private static let samples: [Sample] = ["web", "db", "jobs"].enumerated().flatMap { index, host in
        (0..<60).map { minute in
            let wave = sin(Double(minute) / (5 + Double(index) * 2)) * 12
            let base = [38.0, 22, 14][index] + Double((minute * (7 + index * 3)) % 9)
            return Sample(minute: minute, host: host, load: max(2, base + wave + (host == "jobs" && minute > 48 ? 35 : 0)))
        }
    }
    private static let files: [(String, String, String)] = [
        ("folder.fill", "backups", "—"), ("folder.fill", "releases", "—"), ("doc.text", "compose.yaml", "2 KB"),
        ("doc.text", "nginx.conf", "4 KB"), ("doc.zipper", "shop-2.14.tar.gz", "48 MB"),
        ("doc.text", "README.md", "6 KB"), ("terminal", "deploy.sh", "3 KB"),
    ]

    /// The windows' drop below where they stand on a 1920 × 1080 screen: half of a taller screen's extra height.
    private var below: CGFloat { max(0, size.height - 1080) / 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.18, blue: 0.32), Color(red: 0.28, green: 0.20, blue: 0.42),
                                    Color(red: 0.62, green: 0.36, blue: 0.40)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.06)).frame(width: 900).offset(x: 1200, y: -200)
            Circle().fill(.white.opacity(0.04)).frame(width: 600).offset(x: -150, y: 650)

            HStack {
                Text("Applications").fontWeight(.semibold)
                Spacer()
                // Today, as the Mac's menu bar beside it says (9:41 there too, site_shots.sh).
                Text("\(Date.now.formatted(.dateTime.weekday(.abbreviated))) 09:41").fontWeight(.semibold)
                Spacer()
                Image(systemName: "network"); Image(systemName: "speaker.wave.2.fill"); Image(systemName: "battery.75percent")
            }
            .font(.system(size: 20)).foregroundStyle(.white)
            .padding(.horizontal, 24).frame(height: 44).background(.black.opacity(0.75))

            window(title: "Monitoring — shop", width: 1080, height: 640) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 40) {
                        stat("Requests / min", "1,284"); stat("p95 latency", "182 ms"); stat("Queue", "37", alert: true)
                    }
                    Text("CPU, last hour").font(.system(size: 22, weight: .semibold))
                    Chart(Self.samples) {
                        LineMark(x: .value("Minute", $0.minute), y: .value("CPU %", $0.load))
                            .foregroundStyle(by: .value("Host", $0.host))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...100)
                    .chartForegroundStyleScale(["web": .blue, "db": .green, "jobs": .orange])
                }
            }
            .offset(x: 90, y: 110 + below)

            window(title: "~/shop", width: 620, height: 520) {
                VStack(spacing: 0) {
                    ForEach(Self.files, id: \.1) { icon, name, size in
                        HStack(spacing: 16) {
                            Image(systemName: icon).foregroundStyle(icon == "folder.fill" ? .blue : .secondary).frame(width: 30)
                            Text(name)
                            Spacer()
                            Text(size).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 22)).padding(.vertical, 14)
                        Divider()
                    }
                }
            }
            .offset(x: 1230, y: 360 + below)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)
    }

    private func stat(_ label: String, _ value: String, alert: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 18)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 36, weight: .bold)).foregroundStyle(alert ? .orange : .primary)
        }
    }

    private func window<Content: View>(title: String, width: CGFloat, height: CGFloat,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 20, weight: .semibold))
                Spacer()
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.gray.opacity(0.4)).frame(width: 18) }
            }
            .padding(.horizontal, 20).frame(height: 52).background(Color(white: 0.9))
            content().padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, height: height)
        .background(.white)
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }
}
#endif
