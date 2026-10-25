#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import GlassDatabase

/// Frame cost of scrolling the real database grid (2026-09-23: *"I think this is going to sneak up
/// on us in the Database and Terminal areas too"*). The real `TableDetailView`, the real session
/// manager and a real SQLite file of 10,000 rows × 20 columns in the app's managed folder, deleted
/// afterwards. Runs only when `GPT_GRID_TIMING` is set; prints per-frame times per page size.
@Suite("Database grid scrolling cost", .serialized)
@MainActor
struct GridScrollTimingTests {
    private static let rows = 10_000
    private static let columns = 20

    private func makeDatabase() throws -> URL {
        let folder = try SQLiteFileImporter.managedDirectory(create: true)
        let url = folder.appendingPathComponent("gpt-grid-timing-\(UUID().uuidString).sqlite")
        let columnList = (1...Self.columns).map { "c\($0)" }.joined(separator: ", ")
        let values = (1...Self.columns).map { i in
            i % 3 == 0 ? "n * \(i)" : (i % 3 == 1 ? "'row ' || n || ' column \(i) text'" : "printf('%.2f', n / \(i).0)")
        }.joined(separator: ", ")
        let sql = """
        CREATE TABLE t (id INTEGER PRIMARY KEY, \(columnList));
        WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < \(Self.rows))
        INSERT INTO t (\(columnList)) SELECT \(values) FROM s;
        """
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [url.path(percentEncoded: false), sql]
        try process.run()
        process.waitUntilExit()
        return url
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func measure(pageSize: Int, database: URL) async throws {
        let config = DatabaseConnectionConfig(name: "grid timing", engine: .sqlite,
                                              host: database.path(percentEncoded: false), port: 0, username: "")
        let manager = DatabaseSessionManager(loadImmediately: false)
        let sessionID = try await manager.connect(config: config, password: "")
        defer { Task { await manager.disconnect(sessionID: sessionID) } }
        var state = GridQueryState()
        state.pageSize = pageSize
        let key = GridQueryState.storageKey(connectionID: config.id, database: "main", table: "t")
        UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let settings = SettingsManager(loadImmediately: false)
        let host = NSHostingView(rootView: TableDetailView(sessionID: sessionID, database: "main", table: "t")
            .environment(manager).environment(settings))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1400, height: 900),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }

        // Wait for the page to load: the grid's scroll view grows tall once its rows are there.
        let clock = ContinuousClock()
        let loadStart = clock.now
        var grid: NSScrollView?
        while clock.now - loadStart < .seconds(30) {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            grid = scrollViews(in: host)
                .filter { ($0.documentView?.frame.height ?? 0) > CGFloat(min(pageSize, 50)) * 20 }
                .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
            if grid != nil { break }
        }
        let loaded = clock.now - loadStart
        guard let grid else {
            Issue.record("the grid never showed \(pageSize) rows")
            return
        }

        let before = grid.contentView.bounds.origin.y
        let frames = scrollFrames(grid: grid, host: host)
        print(String(format: "GRID page %d: document height %.0f pt (%.1f pt a row), scrolled from %.0f to %.0f",
                     pageSize, grid.documentView?.frame.height ?? 0,
                     (grid.documentView?.frame.height ?? 0) / Double(pageSize),
                     before, grid.contentView.bounds.origin.y))
        let sorted = frames.sorted()
        print(String(format: "GRID page %d: load %.2f s, scroll median %.1f ms, p95 %.1f ms, max %.1f ms, over 16.7 ms: %d/%d",
                     pageSize, Double(loaded.components.seconds) + Double(loaded.components.attoseconds) / 1e18,
                     sorted[sorted.count / 2], sorted[sorted.count * 95 / 100], sorted.last!, frames.filter { $0 > 16.7 }.count, frames.count))
    }

    /// Synchronous so it can turn the run loop, which SwiftUI needs to apply scroll-driven updates.
    private func scrollFrames(grid: NSScrollView, host: NSView) -> [Double] {
        let clock = ContinuousClock()
        var frames: [Double] = []
        for step in 1...(Int(ProcessInfo.processInfo.environment["GPT_GRID_STEPS"] ?? "") ?? 120) {
            let start = clock.now
            grid.contentView.scroll(to: NSPoint(x: 0, y: Double(step) * 40))
            grid.reflectScrolledClipView(grid.contentView)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            host.displayIfNeeded()
            let d = clock.now - start
            frames.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }
        return frames
    }

    /// A measurement, printed, not a check: run with GPT_GRID_TIMING set.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPT_GRID_TIMING"] != nil, "a timing probe: set GPT_GRID_TIMING"))
    func frames() async throws {
        let database = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: database) }
        let sizes = ProcessInfo.processInfo.environment["GPT_GRID_PAGE"].flatMap(Int.init).map { [$0] } ?? [100, 1_000, 10_000]
        for pageSize in sizes {
            try await measure(pageSize: pageSize, database: database)
        }
    }
}
#endif
