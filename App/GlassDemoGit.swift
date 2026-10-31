//
//  GlassDemoGit.swift
//  Glass Power Tools
//
//  Screenshots only (2026-10-30, the owner: the site shows no Git in the editor): the made-up shop
//  as a real Git repository — a few weeks of history, a merged branch, a release branch, a tag, a
//  stash, and changes staged, unstaged, new and deleted — for the editor's Changes, History and
//  Blame. Made with the Mac's own `git`: in the app on a Mac, and in the iPhone, iPad and Vision Pro
//  simulators, which run on a Mac and can start it (`GlassEditorLocalFileAccess.demoGitRunner`).
//  DEBUG-only, and only alongside `--ui-testing`, as the rest of the demo.
//

#if DEBUG && (os(macOS) || targetEnvironment(simulator))
import Foundation
import Darwin
import GlassEditor

/// A program run to its end, its output read.
nonisolated enum GlassDemoProcess {
    /// The Mac's `git`, as the editor finds it: Homebrew's, else the developer tools'.
    static let git: String? = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Runs `executable` with `arguments` and nothing of the app's environment but `environment`,
    /// off the main thread.
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil,
                    environment: [String: String] = [:]) async -> GlassEditorCommandOutput {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runNow(executable, arguments, input: input, environment: environment))
            }
        }
    }

    private static func runNow(_ executable: String, _ arguments: [String], input: Data?,
                               environment: [String: String]) -> GlassEditorCommandOutput {
        var stdin: [Int32] = [0, 0], stdout: [Int32] = [0, 0], stderr: [Int32] = [0, 0]
        guard pipe(&stdin) == 0, pipe(&stdout) == 0, pipe(&stderr) == 0 else {
            return GlassEditorCommandOutput(exitStatus: nil, standardOutput: Data())
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdin[0], 0)
        posix_spawn_file_actions_adddup2(&actions, stdout[1], 1)
        posix_spawn_file_actions_adddup2(&actions, stderr[1], 2)
        for descriptor in stdin + stdout + stderr { posix_spawn_file_actions_addclose(&actions, descriptor) }

        var base = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "LANG": "en_US.UTF-8",
                    "HOME": NSTemporaryDirectory(), "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"]
        base.merge(environment) { _, given in given }
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = base.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, nil, argv, envp)
        close(stdin[0]); close(stdout[1]); close(stderr[1])
        guard spawned == 0 else {
            close(stdin[1]); close(stdout[0]); close(stderr[0])
            return GlassEditorCommandOutput(exitStatus: 127, standardOutput: Data())
        }
        if let input { input.withUnsafeBytes { _ = write(stdin[1], $0.baseAddress, $0.count) } }
        close(stdin[1])
        // Both read at once: a full pipe on one would hold the other.
        var errors = Data()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global().async { errors = readAll(stderr[0]); reading.leave() }
        let output = readAll(stdout[0])
        reading.wait()
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let exited = status & 0x7F == 0
        return GlassEditorCommandOutput(exitStatus: exited ? Int((status >> 8) & 0xFF) : nil,
                                        standardOutput: output, standardError: errors)
    }

    private static func readAll(_ descriptor: Int32) -> Data {
        defer { close(descriptor) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }
}

/// The Mac's `git`, from a simulator.
@MainActor
struct GlassDemoGitRunner: GlassEditorGitRunner {
    func git(_ arguments: [String], in directory: String) async throws -> GlassEditorCommandOutput {
        try await run(arguments, in: directory, input: nil)
    }

    func git(_ arguments: [String], in directory: String, input: Data) async throws -> GlassEditorCommandOutput {
        try await run(arguments, in: directory, input: input)
    }

    private func run(_ arguments: [String], in directory: String, input: Data?) async throws -> GlassEditorCommandOutput {
        guard let git = GlassDemoProcess.git else { throw GlassEditorGitError.notInstalled }
        return await GlassDemoProcess.run(git, ["-C", directory] + arguments, input: input)
    }
}

/// The made-up shop's history.
@MainActor
enum GlassDemoShop {
    /// Makes the shop at `root` a repository with its history and today's changes. False when
    /// there is no `git` to make it with.
    static func makeRepository(at root: URL) async -> Bool {
        guard let git = GlassDemoProcess.git else { return false }
        let files = FileManager.default
        try? files.removeItem(at: root)
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
        var failed = false
        func write(_ written: [(String, String)]) {
            for (path, text) in written {
                let url = root.appending(path: path)
                try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(text.utf8).write(to: url)
            }
        }
        func run(_ arguments: [String], on day: String = "2026-10-01T09:00:00", as author: (String, String) = ann) async {
            let output = await GlassDemoProcess.run(git, ["-C", root.path] + arguments, environment: [
                "GIT_AUTHOR_NAME": author.0, "GIT_AUTHOR_EMAIL": author.1, "GIT_AUTHOR_DATE": day + "+02:00",
                "GIT_COMMITTER_NAME": author.0, "GIT_COMMITTER_EMAIL": author.1, "GIT_COMMITTER_DATE": day + "+02:00",
            ])
            if output.exitStatus != 0 { failed = true }
        }
        func commit(_ message: String, on day: String, as author: (String, String) = ann) async {
            await run(["add", "-A"], on: day, as: author)
            await run(["commit", "--quiet", "-m", message], on: day, as: author)
        }

        await run(["init", "--quiet", "--initial-branch=main"])
        write(GlassDemoShopFiles.first)
        await commit("Start the shop: storefront, admin and the job runner", on: "2026-09-14T10:12:00")
        write(GlassDemoShopFiles.products)
        await commit("Products: SKU is unique per catalog", on: "2026-09-29T15:40:00", as: ben)
        await run(["switch", "--quiet", "-c", "stock-alerts"])
        write(GlassDemoShopFiles.stockAlerts)
        await commit("Alert when stock falls under ten", on: "2026-10-06T11:05:00", as: ben)
        await run(["switch", "--quiet", "main"])
        await run(["merge", "--quiet", "--no-ff", "-m", "Merge branch 'stock-alerts'", "stock-alerts"], on: "2026-10-08T09:30:00")
        write(GlassDemoShopFiles.orders)
        await commit("Orders: page the admin list by 50", on: "2026-10-15T16:22:00")
        await run(["tag", "-a", "v2.14.1", "-m", "Release 2.14.1"], on: "2026-10-15T16:30:00")
        await run(["branch", "release/2.15"])
        write(GlassDemoShopFiles.lastAddress)
        await commit("Checkout remembers the last shipping address", on: "2026-10-27T10:48:00")
        // Put by: receipts in the customer's language, half done.
        write(GlassDemoShopFiles.stashed)
        await run(["stash", "push", "--quiet", "-m", "Receipts in the customer's language"], on: "2026-10-28T17:02:00")
        // Today: the relay staged; the address checks and the README changed; a file new, one gone.
        write(GlassDemoShopFiles.staged)
        await run(["add", "compose.yaml"])
        write(GlassDemoShopFiles.working)
        try? files.removeItem(at: root.appending(path: "Sources/Admin/LegacyExport.swift"))
        return !failed
    }

    private static let ann = ("Ann Example", "ann@example.com")
    private static let ben = ("Ben Example", "ben@example.com")
}

/// The shop's files at each step of its history.
enum GlassDemoShopFiles {
    static let shippingAddress = """
    import Foundation

    /// The address an order ships to.
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
        mutating func ship(to address: ShippingAddress) throws {
            guard address.missingFields.isEmpty else {
                throw CheckoutError.incompleteAddress(address.missingFields)
            }
            self.address = address
            step = .payment
        }
    }

    """

    static let compose = """
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

    """

    static let readme = """
    # shop

    The storefront, its admin and the job runner, deployed with Compose.

    ## Deploying

    1. Tag the release: `git tag v2.14.1`
    2. Run `./deploy.sh alpha`
    3. Watch `docker compose logs -f jobs` until the queue drains.

    """

    static let first: [(String, String)] = [
        ("README.md", readme),
        ("compose.yaml", compose),
        ("deploy.sh", "#!/bin/sh\nset -eu\nssh \"$1\" 'cd shop && docker compose pull && docker compose up -d'\n"),
        ("Sources/Checkout/ShippingAddress.swift", shippingAddress),
        ("Sources/Jobs/SendReceipt.swift", """
        import Foundation

        /// Sends an order's receipt through the mail relay, retrying for an hour.
        struct SendReceipt: Job {
            let order: Order.ID

            func run(in context: JobContext) async throws {
                let order = try await context.orders.find(order)
                let mail = Receipt(order: order).message()
                try await context.mail.send(mail, retryingFor: .hours(1))
            }
        }

        """),
        ("Sources/Admin/LegacyExport.swift", """
        import Foundation

        /// The CSV export the old admin offered. Nothing links to it any more.
        enum LegacyExport {
            static func csv(_ orders: [Order]) -> String {
                orders.map { "\\($0.id),\\($0.total)" }.joined(separator: "\\n")
            }
        }

        """),
    ]

    static let products: [(String, String)] = [
        ("Sources/Catalog/Product.swift", """
        import Foundation

        struct Product: Codable, Identifiable, Sendable {
            let id: UUID
            var name: String
            /// Unique within its catalog.
            var sku: String
            var price: Decimal
            var stock: Int
        }

        """),
    ]

    static let stockAlerts: [(String, String)] = [
        ("Sources/Catalog/StockAlert.swift", """
        import Foundation

        /// Tells the shop's staff when a product is running out.
        struct StockAlert: Sendable {
            static let threshold = 10

            static func products(_ products: [Product]) -> [Product] {
                products.filter { $0.stock < threshold }
            }
        }

        """),
    ]

    static let orders: [(String, String)] = [
        ("Sources/Admin/OrderList.swift", """
        import Foundation

        /// The admin's list of orders, newest first, fifty to a page.
        struct OrderList {
            static let pageSize = 50

            func page(_ number: Int, of orders: [Order]) -> ArraySlice<Order> {
                let start = number * Self.pageSize
                return orders.sorted { $0.placedAt > $1.placedAt }
                    .dropFirst(start).prefix(Self.pageSize)
            }
        }

        """),
    ]

    static let lastAddress: [(String, String)] = [
        ("Sources/Checkout/ShippingAddress.swift", shippingAddress
            .replacingOccurrences(of: "/// The address an order ships to.",
                                  with: "/// The address an order ships to. Checkout offers the customer's last one first.")
            .replacingOccurrences(of: "extension CheckoutSession {\n    mutating func ship",
                                  with: "extension CheckoutSession {\n"
                                    + "    /// The address used last time, if the customer has ordered before.\n"
                                    + "    func lastAddress(of customer: Customer.ID) async throws -> ShippingAddress? {\n"
                                    + "        let recent = try await orders.latest(for: customer, limit: 1)\n"
                                    + "        return recent.first?.shippingAddress\n"
                                    + "    }\n\n"
                                    + "    mutating func ship")),
    ]

    static let stashed: [(String, String)] = [
        ("Sources/Jobs/SendReceipt.swift", """
        import Foundation

        /// Sends an order's receipt through the mail relay, retrying for an hour.
        struct SendReceipt: Job {
            let order: Order.ID

            func run(in context: JobContext) async throws {
                let order = try await context.orders.find(order)
                let customer = try await context.customers.find(order.customer)
                let mail = Receipt(order: order, language: customer.language).message()
                try await context.mail.send(mail, retryingFor: .hours(1))
            }
        }

        """),
    ]

    static let staged: [(String, String)] = [
        ("compose.yaml", compose.replacingOccurrences(of: "SMTP_HOST: mail.example.com", with: "SMTP_HOST: relay.example.com")),
    ]

    static let working: [(String, String)] = [
        ("Sources/Checkout/ShippingAddress.swift", lastAddress[0].1
            .replacingOccurrences(of: "(\"city\", city), (\"postal code\", postalCode)]",
                                  with: "(\"city\", city), (\"postal code\", postalCode), (\"country\", country)]")
            .replacingOccurrences(of: "    }\n}\n\nextension CheckoutSession {",
                                  with: "    }\n\n"
                                    + "    /// The lines a label prints, the country last and in capitals.\n"
                                    + "    var labelLines: [String] {\n"
                                    + "        [name, street, \"\\(postalCode) \\(city)\", country.uppercased()]\n"
                                    + "    }\n}\n\nextension CheckoutSession {")),
        ("README.md", readme.replacingOccurrences(of: "2. Run `./deploy.sh alpha`",
                                                  with: "2. Run `./deploy.sh alpha` (it pulls the images first)")),
        ("Sources/Checkout/AddressBook.swift", """
        import Foundation

        /// A customer's saved addresses, the last one used first.
        struct AddressBook: Codable, Sendable {
            var addresses: [ShippingAddress] = []

            mutating func use(_ address: ShippingAddress) {
                addresses.removeAll { $0 == address }
                addresses.insert(address, at: 0)
            }
        }

        """),
    ]
}
#endif
