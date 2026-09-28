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
                    layers: GlassLayerStore) async {
        guard !didRun, let surface = requestedSurface else { return }
        didRun = true
        // The theme colour behind content, so a window reads against the simulator's bright room.
        // A setting anyone can choose (Settings ▸ Appearance); the default paints none.
        layers.state.opacity = 0.9
        switch surface {
        case "editor", "preview":
            await openEditor(editor, preview: surface == "preview")
        case "terminal":
            terminal.requestDemoReplay(name: "alpha", output: Data(terminalTranscript.utf8))
        case "database":
            // Put there by Tools/Screenshots/shoot.sh, from make-demo-db.py.
            database.requestDemoDatabase(file: URL.documentsDirectory.appending(path: "demo-shop.sqlite"), name: "shop")
        case "desktop":
            let renderer = ImageRenderer(content: DemoRemoteScreen())
            renderer.scale = 1
            guard let picture = renderer.cgImage else { return }
            await desktop.requestDemoDesktop(name: "bravo", host: "192.0.2.20", picture: picture)
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
    /// the Swift one in front; for `preview`, the README with its rendered preview beside it.
    private static func openEditor(_ editor: GlassEditorRuntime, preview: Bool) async {
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
        let order = preview
            ? ["compose.yaml", "Sources/Checkout/ShippingAddress.swift", "README.md"]
            : ["compose.yaml", "README.md", "Sources/Checkout/ShippingAddress.swift"]
        var last: GlassEditorDocument?
        for path in order { last = await workspace.open(root.appending(path: path)) }
        if preview, let last { workspace.previewModes[last.id] = .beside }
        editor.present(window)
    }

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
