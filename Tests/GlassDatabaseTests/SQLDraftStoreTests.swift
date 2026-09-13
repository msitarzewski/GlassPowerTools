//
//  SQLDraftStoreTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  R1: glassdb lost unsaved SQL on window close and app quit. These cover the three things that
//  distinguish a fix from a feature — the draft survives the process, a deliberate tab close
//  discards it, and the store cannot grow without bound — plus the file being untrusted input.
//

import Foundation
import Testing
@testable import GlassDatabase

@MainActor
@Suite("SQL drafts")
struct SQLDraftStoreTests {

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory
            .appendingPathComponent("gpt-sql-drafts-\(UUID().uuidString)", isDirectory: true)
    }

    /// Writes are debounced in the app; tests flush explicitly, which is also the production path
    /// on scene background and window close.
    private func makeStore(_ directory: URL) -> SQLDraftStore {
        SQLDraftStore(directory: directory, debounceInterval: .milliseconds(1))
    }

    private func range(_ location: Int, _ length: Int = 0) -> NSRange {
        NSRange(location: location, length: length)
    }

    // MARK: The defect

    @Test("A draft written in one process is there in the next")
    func draftSurvivesTheProcess() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let tab = UUID()

        let first = makeStore(directory)
        first.record(sql: "SELECT 1;", selection: .query(id: tab), selectedRange: range(3, 2), connectionID: connection)
        first.flush()

        // A second store over the same directory is what a relaunch looks like.
        let second = makeStore(directory)
        let drafts = second.drafts(for: connection)
        #expect(drafts.count == 1)
        #expect(drafts.first?.sql == "SELECT 1;")
        #expect(drafts.first?.clampedSelection == range(3, 2))
        #expect(drafts.first?.selection == .query(id: tab))
    }

    @Test("Closing a tab deliberately discards its draft; closing the window does not")
    func closingATabDiscardsOnlyThatDraft() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let closed = UUID()
        let kept = UUID()

        let store = makeStore(directory)
        store.record(sql: "SELECT 1;", selection: .query(id: closed), selectedRange: range(0), connectionID: connection)
        store.record(sql: "SELECT 2;", selection: .query(id: kept), selectedRange: range(0), connectionID: connection)
        store.remove(selection: .query(id: closed), connectionID: connection)
        // The window going away only flushes — it never removes.
        store.flush()

        let reopened = makeStore(directory)
        let drafts = reopened.drafts(for: connection)
        #expect(drafts.map(\.sql) == ["SELECT 2;"])
    }

    @Test("A table's SQL draft is durable too, keyed by its table")
    func tableDraftsAreDurable() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let selection = WorkspaceSelection.table(database: "gpt_test", table: "members")

        let store = makeStore(directory)
        store.record(sql: "UPDATE members SET name = 'x'", selection: selection, selectedRange: range(0), connectionID: connection)
        store.flush()

        #expect(makeStore(directory).drafts(for: connection).first?.selection == selection)
    }

    @Test("An untouched editor never reaches the disk, and emptying one clears it")
    func whitespaceIsNotADraft() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let tab = UUID()

        let store = makeStore(directory)
        store.record(sql: "   \n\t ", selection: .query(id: tab), selectedRange: range(0), connectionID: connection)
        store.flush()
        #expect(makeStore(directory).drafts(for: connection).isEmpty)

        store.record(sql: "SELECT 1;", selection: .query(id: tab), selectedRange: range(0), connectionID: connection)
        store.record(sql: "", selection: .query(id: tab), selectedRange: range(0), connectionID: connection)
        store.flush()
        #expect(makeStore(directory).drafts(for: connection).isEmpty)
        // The file is removed rather than left holding an empty array.
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(connection.uuidString).appendingPathExtension("json").path))
    }

    @Test("The debounced write lands on its own, without a flush")
    func debouncedWriteLandsWithoutFlush() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()

        let store = makeStore(directory)
        store.record(sql: "SELECT 1;", selection: .query(id: UUID()), selectedRange: range(0), connectionID: connection)

        // Polled rather than slept: the debounce is 1 ms here, but the whole suite shares this
        // actor, so a fixed sleep asserts the scheduler's load rather than the store's behaviour.
        var landed: [String] = []
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            landed = makeStore(directory).drafts(for: connection).map(\.sql)
            if !landed.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(landed == ["SELECT 1;"])
    }

    @Test("Moving the caret alone schedules no write; the window closing persists it")
    func caretMovesDoNotWrite() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let tab = UUID()

        let store = makeStore(directory)
        store.record(sql: "SELECT 1;", selection: .query(id: tab), selectedRange: range(0), connectionID: connection)
        store.flush()

        // A caret move on a draft that can be megabytes must not cost a file write.
        store.record(sql: "SELECT 1;", selection: .query(id: tab), selectedRange: range(7), connectionID: connection)
        // Generous on purpose: the point is that *no* write is scheduled, so waiting longer than
        // the debounce can only strengthen it.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(makeStore(directory).drafts(for: connection).first?.clampedSelection == range(0))

        // Closing the window (or leaving the foreground) flushes it out.
        store.flush()
        #expect(makeStore(directory).drafts(for: connection).first?.clampedSelection == range(7))
    }

    // MARK: Which workspace restores

    @Test("A second window on the same connection does not duplicate the tabs")
    func onlyOneWorkspaceRestores() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let store = makeStore(directory)
        store.record(sql: "SELECT 1;", selection: .query(id: UUID()), selectedRange: range(0), connectionID: connection)
        store.flush()

        let primary = UUID()
        let secondWindow = UUID()
        #expect(store.claimDrafts(connectionID: connection, workspace: primary).count == 1)
        #expect(store.claimDrafts(connectionID: connection, workspace: secondWindow).isEmpty)
        // The claimant asking twice is idempotent, not a second restore of nothing.
        #expect(store.claimDrafts(connectionID: connection, workspace: primary).count == 1)

        store.releaseDrafts(connectionID: connection, workspace: secondWindow)
        #expect(store.claimDrafts(connectionID: connection, workspace: secondWindow).isEmpty)

        store.releaseDrafts(connectionID: connection, workspace: primary)
        #expect(store.claimDrafts(connectionID: connection, workspace: secondWindow).count == 1)
    }

    @Test("Drafts do not follow a tab opened against a different connection")
    func draftsAreScopedToTheirConnection() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let tab = UUID()
        let original = UUID()
        let other = UUID()

        let store = makeStore(directory)
        store.record(sql: "SELECT * FROM members;", selection: .query(id: tab), selectedRange: range(0), connectionID: original)
        store.flush()

        #expect(store.drafts(for: other).isEmpty)
        #expect(store.claimDrafts(connectionID: other, workspace: UUID()).isEmpty)
        #expect(store.drafts(for: original).count == 1)
    }

    // MARK: Pruning

    @Test("Over the count cap, the least recently updated goes and the live tab stays")
    func prunesByCount() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let live = WorkspaceSelection.query(id: UUID())
        var drafts = (0..<SQLDraftStore.maximumDraftsPerConnection).map { index in
            SQLDraftRecord(
                selection: .query(id: UUID()),
                sql: "SELECT \(index);",
                selectionLocation: 0,
                selectionLength: 0,
                createdAt: base,
                updatedAt: base.addingTimeInterval(Double(index) + 1)
            )
        }
        let oldest = drafts[0].selection
        drafts.append(SQLDraftRecord(
            selection: live, sql: "SELECT live;", selectionLocation: 0, selectionLength: 0,
            createdAt: base, updatedAt: base
        ))

        let kept = SQLDraftStore.pruned(drafts, keeping: live)
        #expect(kept.count == SQLDraftStore.maximumDraftsPerConnection)
        // `live` has the oldest `updatedAt` of them all and is still kept: the record being
        // written can never evict itself.
        #expect(kept.contains { $0.selection == live })
        #expect(!kept.contains { $0.selection == oldest })
    }

    @Test("Over the byte cap, drafts are evicted until it fits")
    func prunesByBytes() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let live = WorkspaceSelection.query(id: UUID())
        let chunk = String(repeating: "x", count: 3 * 1_024 * 1_024)
        let drafts = [
            SQLDraftRecord(selection: .query(id: UUID()), sql: chunk, selectionLocation: 0, selectionLength: 0,
                           createdAt: base, updatedAt: base.addingTimeInterval(1)),
            SQLDraftRecord(selection: .query(id: UUID()), sql: chunk, selectionLocation: 0, selectionLength: 0,
                           createdAt: base, updatedAt: base.addingTimeInterval(2)),
            SQLDraftRecord(selection: live, sql: chunk, selectionLocation: 0, selectionLength: 0,
                           createdAt: base, updatedAt: base.addingTimeInterval(3))
        ]

        let kept = SQLDraftStore.pruned(drafts, keeping: live)
        #expect(kept.reduce(0) { $0 + $1.byteCount } <= SQLDraftStore.maximumBytesPerConnection)
        #expect(kept.contains { $0.selection == live })
    }

    @Test("A connection file nothing has touched for the expiry window is deleted")
    func prunesExpiredFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = UUID()
        let fresh = UUID()

        let store = makeStore(directory)
        store.record(sql: "SELECT stale;", selection: .query(id: UUID()), selectedRange: range(0), connectionID: stale)
        store.record(sql: "SELECT fresh;", selection: .query(id: UUID()), selectedRange: range(0), connectionID: fresh)
        store.flush()

        let staleURL = directory.appendingPathComponent(stale.uuidString).appendingPathExtension("json")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-SQLDraftStore.expiry - 60)],
            ofItemAtPath: staleURL.path
        )

        // Pruning runs once, on the next store's first read.
        let relaunched = makeStore(directory)
        #expect(relaunched.drafts(for: fresh).count == 1)
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
    }

    @Test("Deleting a connection can delete its drafts outright")
    func removeAllDeletesTheFile() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let store = makeStore(directory)
        store.record(sql: "SELECT 1;", selection: .query(id: UUID()), selectedRange: range(0), connectionID: connection)
        store.flush()

        store.removeAll(connectionID: connection)
        #expect(makeStore(directory).drafts(for: connection).isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(connection.uuidString).appendingPathExtension("json").path))
    }

    // MARK: The file is untrusted input

    @Test("A selection beyond the text cannot escape the string")
    func selectionIsClamped() {
        let record = SQLDraftRecord(
            selection: .query(id: UUID()), sql: "SELECT 1;",
            selectionLocation: 9_000, selectionLength: 9_000,
            createdAt: .now, updatedAt: .now
        )
        #expect(record.clampedSelection == NSRange(location: 9, length: 0))

        let negative = SQLDraftRecord(
            selection: .query(id: UUID()), sql: "SELECT 1;",
            selectionLocation: -5, selectionLength: -5,
            createdAt: .now, updatedAt: .now
        )
        #expect(negative.clampedSelection == NSRange(location: 0, length: 0))

        let overlong = SQLDraftRecord(
            selection: .query(id: UUID()), sql: "SELECT 1;",
            selectionLocation: 4, selectionLength: 500,
            createdAt: .now, updatedAt: .now
        )
        #expect(overlong.clampedSelection == NSRange(location: 4, length: 5))
    }

    @Test("A file from a newer version is left alone rather than read or overwritten")
    func futureVersionsAreLeftAlone() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(connection.uuidString).appendingPathExtension("json")
        let future = Data("""
        {"version":99,"connectionID":"\(connection.uuidString)","drafts":[]}
        """.utf8)
        try future.write(to: url)

        let store = makeStore(directory)
        #expect(store.drafts(for: connection).isEmpty)
        // Nothing was written, so a build that understands version 99 still finds its drafts.
        store.flush()
        let afterFlush = try Data(contentsOf: url)
        #expect(afterFlush == future)
    }

    @Test("Unreadable JSON is reported, not crashed on")
    func corruptFilesAreSurvivable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent(connection.uuidString).appendingPathExtension("json"))

        #expect(makeStore(directory).drafts(for: connection).isEmpty)
    }

    @Test("Restored drafts come back in the order they were created")
    func restoreOrderIsStable() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = UUID()
        let store = makeStore(directory)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<3 {
            store.record(
                sql: "SELECT \(index);",
                selection: .query(id: UUID()),
                selectedRange: range(0),
                connectionID: connection,
                now: base.addingTimeInterval(Double(3 - index))
            )
        }
        store.flush()

        #expect(makeStore(directory).drafts(for: connection).map(\.sql) == ["SELECT 2;", "SELECT 1;", "SELECT 0;"])
    }

    // MARK: Tabs

    @Test("Restoring tabs does not steal the selection")
    func restoringTabsKeepsTheSelection() {
        var state = WorkspaceTabState(initialSelection: .connection)
        let first = WorkspaceSelection.query(id: UUID())
        let second = WorkspaceSelection.query(id: UUID())

        state.restore([first, second, first])
        #expect(state.tabs == [.connection, first, second])
        #expect(state.selected == .connection)
        #expect(state.displayed == .connection)
    }
}
