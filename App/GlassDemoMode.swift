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

@MainActor
enum GlassDemoMode {
    private static var didRun = false

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
        // `--demo-glass <opacity>,<frost>`: Appearance's two sliders, for checking a window's glass
        // at a given setting (a Vision Pro terminal at Blur 0 is completely clear).
        let arguments = ProcessInfo.processInfo.arguments
        var demoGlass: (opacity: Double, frost: Double)?
        if let index = arguments.firstIndex(of: "--demo-glass"), arguments.indices.contains(index + 1) {
            let values = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
            if values.count == 2 {
                layers.state.opacity = values[0]
                layers.state.frost = values[1]
                demoGlass = (values[0], values[1])
            }
        }
        #if os(iOS)
        // `--demo-landscape`: the iPhone turned on its side, for checking the landscape layout
        // without driving the Simulator app's rotate menu.
        if ProcessInfo.processInfo.arguments.contains("--demo-landscape"),
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
        #endif
        switch surface {
        case "editor", "preview":
            await openEditor(editor, preview: surface == "preview")
        case "editor-model":
            // A 3D model in the editor's viewer (D78): RealityKit on the Mac, iPhone and iPad, and
            // Apple's Quick Look volume as it opens on Vision Pro. Written here, as the project is.
            await openEditor(editor, preview: false, model: true)
        case "editor-window", "editor-settings":
            // A window with settings of its own (W23), and This Window open over it.
            await openEditor(editor, preview: false, windowSettings: GlassEditorRuntime.demoWindowSettings,
                             opensSettings: surface == "editor-settings")
        case "terminal":
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8))
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
        case "terminal-tmux":
            // 2026-10-15: tmux as SwiftTerm sees it — the alternate screen, the mouse asked for, and
            // a status line redrawn every 0.4 s — over words to select (the owner: "selecting text is
            // still broken wholly in the terminal in visionOS with tmux").
            let words = String(repeating: "select these words on the screen ", count: 4)
            let screen = "\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h\u{1B}[H\u{1B}[2J"
                + Array(repeating: words, count: 60).joined(separator: "\r\n")
            let status = "\u{1B}7\u{1B}[999;1H\u{1B}[7m[0] 0:zsh*  \u{1B}[0m\u{1B}8"
            terminal.requestDemoReplay(name: "alpha", output: Data(screen.utf8), tick: Data(status.utf8))
        case "terminal-window", "terminal-settings":
            // A window with settings of its own (W22), and This Window open over it.
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8),
                                       windowSettings: GlassTerminalRuntime.demoWindowSettings,
                                       opensSettings: surface == "terminal-settings")
        case "terminal-move":
            // Two windows of one terminal each (W26): the tools menu's Move Tab To lists the other,
            // and either title drags into the other window.
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8))
            terminal.requestDemoReplay(name: "bravo", output: Data("ann@bravo:~$ ".utf8))
        case "library-history":
            // The library's overview with a month of invented connections behind it: the chart and
            // Most used, for checking how its tiles and sections line up.
            while !shell.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            var connections: [(host: String, daysAgo: Int, kind: HostServiceKind)] = []
            for day in 0..<30 where day % 3 != 1 {
                connections.append(("alpha", day, day % 2 == 0 ? .ssh : .database))
                if day % 4 == 0 { connections.append(("bravo", day, .rdp)) }
                if day % 5 == 0 { connections.append(("build", day, .ssh)) }
            }
            shell.demoRecordConnections(connections)
            // Two more devices, as iCloud would bring them (D81): the overview's All Devices and
            // its device choice. Invented names, as the rest of the demo's.
            shell.demoOtherDevices([("Studio Mac", [("alpha", .ssh, 3), ("build", .ssh, 2)]),
                                    ("Vision Pro (Lab)", [("bravo", .rdp, 2), ("alpha", .database, 1)])])
        case "terminal-ring":
            // 2026-10-15: ten terminals in one window, for its orb's ring (`--demo-session-orb`, and
            // `--demo-orb-names` to see where every name sits).
            terminal.requestDemoTabs(names: ["build", "logs", "api", "web", "db", "cache", "jobs", "deploy", "docs", "tests"],
                                     output: Data(terminalTranscript.utf8), grid: false)
        case "terminal-tabs", "terminal-grid":
            // W31: one window with two terminals as its tabs, shown in tabs and in the grid, for
            // checking that one bottom bar shows. The shell reports its folder (OSC 7), so Open
            // Folder Here is in the bar as it is on a real shell.
            terminal.requestDemoTabs(names: ["alpha", "bravo"],
                                     output: Data(("\u{1B}]7;/home/ann/shop\u{07}" + terminalTranscript).utf8),
                                     grid: surface == "terminal-grid")
        case "connections-host":
            // The Connections window at its first size with a machine's details showing (W29).
            while !shell.isLoaded { try? await Task.sleep(for: .milliseconds(100)) }
            if let alpha = shell.hosts.first(where: { $0.displayName == "alpha" }) { shell.showHost(alpha.id) }
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
        case "database", "diagram":
            // Put there by Tools/Screenshots/shoot.sh, from make-demo-db.py.
            database.requestDemoDatabase(file: URL.documentsDirectory.appending(path: "demo-shop.sqlite"), name: "shop",
                                         showsDiagram: surface == "diagram")
        case "database-server", "database-main":
            // W32: the server's overview, or the `main` database's, for their titles and tiles.
            database.requestDemoDatabase(file: URL.documentsDirectory.appending(path: "demo-shop.sqlite"), name: "shop",
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
            database.requestDemoDatabase(file: URL.documentsDirectory.appending(path: "demo-shop.sqlite"), name: "shop",
                                         windowSettings: GlassDatabaseRuntime.demoWindowSettings,
                                         opensSettings: surface == "database-settings")
        case "desktop", "desktop-window", "desktop-settings":
            let renderer = ImageRenderer(content: DemoRemoteScreen())
            renderer.scale = 1
            guard let picture = renderer.cgImage else { return }
            // `desktop-window`: a window with settings of its own (W25); `desktop-settings`: and
            // Desktop Settings ▸ This Window open over it. `desktop` with `--demo-glass`: the
            // window's glass is the frost given (a desktop's glass is its own Background Frost,
            // not Appearance's), and an opacity above 0 fades the remote screen — a desktop has no
            // theme to paint, so 0 leaves the screen as it is (W28).
            var windowSettings = surface == "desktop" ? GlassWindowOverrides() : GlassDesktopRuntime.demoWindowSettings
            if surface == "desktop", let demoGlass {
                windowSettings = GlassDesktopRuntime.demoWindowSettings(
                    frost: demoGlass.frost, opacity: demoGlass.opacity > 0 ? demoGlass.opacity : nil)
            }
            await desktop.requestDemoDesktop(
                name: "bravo", host: "192.0.2.20", picture: picture,
                windowSettings: windowSettings,
                opensSettings: surface == "desktop-settings")
        case "all-windows":
            // All Windows (2026-10-14): a window of three terminals as tabs, a desktop and an
            // editor, then All Windows over them, laid out as the Mac's, a card per tab.
            terminal.requestDemoTabs(names: ["alpha", "bravo", "charlie"],
                                     output: Data(terminalTranscript.utf8), grid: false)
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

    /// The invented shop's repository, written into Documents and opened: several files in tabs,
    /// the Swift one in front; for `preview`, the README with its rendered preview beside it. With
    /// `windowSettings`, the window keeps them as its own (W23); with `opensSettings`, Editor
    /// Settings ▸ This Window opens over it.
    private static func openEditor(_ editor: GlassEditorRuntime, preview: Bool,
                                   windowSettings: GlassWindowOverrides = GlassWindowOverrides(),
                                   opensSettings: Bool = false, model: Bool = false) async {
        let root = URL.documentsDirectory.appending(path: "shop", directoryHint: .isDirectory)
        do {
            for (path, text) in projectFiles {
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
        if preview, let last { workspace.previewModes[last.id] = .beside }
        editor.present(window)
    }

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
                Text("Mon 09:41").fontWeight(.semibold)
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
            .offset(x: 90, y: 110)

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
            .offset(x: 1230, y: 360)
        }
        .frame(width: 1920, height: 1080)
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
