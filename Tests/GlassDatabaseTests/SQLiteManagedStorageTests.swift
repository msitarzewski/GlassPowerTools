//
//  SQLiteManagedStorageTests.swift
//  Glass Power Tools — GlassDatabaseTests
//
//  `SQLiteFileImporter.validatedURL` (`SQLiteFileImporter.swift:82`) is the guard that decides
//  whether a path saved in a connection record still points inside the app's managed SQLite
//  storage. It moved into this product from glassdb essentially verbatim and arrived with no
//  tests at all.
//
//  **What makes it load-bearing is the caller, not the reader.**
//  `ConnectionManager.removeUnreferencedSQLiteFile` (`ConnectionManager.swift:275-276`) calls
//  `FileManager.removeItem(at:)` on whatever this function returns, with no second check of its
//  own. `DatabaseConnectionConfig.host` for a SQLite connection is just a string in a persisted
//  record. So a path that escapes managed storage is not a bad read that shows an error — it is a
//  **delete outside the sandbox**, performed silently while the user deletes a connection.
//
//  The four refusals below are therefore asserted individually and by their specific
//  `ImportError`, because the errors are not interchangeable to the caller: it swallows
//  `.managedCopyMissing` as "already gone, nothing to do" and logs anything else. A guard that
//  returned the wrong refusal would still stop the delete, but would stop reporting it.
//
//  The case worth reading twice is `siblingDirectoryThatOnlyPrefixesTheNameIsRefused`. It is the
//  reason the implementation compares `pathComponents` rather than calling `hasPrefix` on the
//  path string, and it is the case a naive rewrite passes without noticing.
//

import Foundation
import Testing
@testable import GlassDatabase

/// Redirects `.applicationSupportDirectory` into a temporary directory so the managed-storage
/// root is a real directory this test owns. Everything else — `fileExists`, `createDirectory`,
/// symbolic links — is the genuine `FileManager`, because the guard's behaviour depends on real
/// filesystem resolution and a fake would prove nothing about it.
private final class TemporaryApplicationSupport: FileManager, @unchecked Sendable {
    private let applicationSupport: URL

    init(applicationSupport: URL) {
        self.applicationSupport = applicationSupport
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        guard directory == .applicationSupportDirectory else {
            return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
        }
        if shouldCreate {
            try createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        }
        return applicationSupport
    }
}

@Suite("SQLite managed storage path guard")
struct SQLiteManagedStorageTests {
    /// A temporary world with the managed directory already created.
    ///
    /// `sandbox` is the enclosing directory: it stands in for everywhere on disk that is *not*
    /// managed storage, so a path that escapes into it is exactly the delete this guard prevents.
    private struct Storage {
        let sandbox: URL
        let fileManager: FileManager
        let managedDirectory: URL
    }

    private func withStorage(_ body: (Storage) throws -> Void) throws {
        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gpt-sqlite-guard-\(UUID().uuidString)", isDirectory: true)
        let applicationSupport = sandbox.appendingPathComponent("Application Support", isDirectory: true)
        let fileManager = TemporaryApplicationSupport(applicationSupport: applicationSupport)
        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let managed = try SQLiteFileImporter.managedDirectory(fileManager: fileManager, create: true)
        try body(Storage(sandbox: sandbox, fileManager: fileManager, managedDirectory: managed))
    }

    @discardableResult
    private func writeFile(at url: URL, fileManager: FileManager) throws -> URL {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not really a database".utf8).write(to: url)
        return url
    }

    /// The refusal a call produced, or nil when it returned a URL.
    private func refusal(
        forPath path: String,
        fileManager: FileManager
    ) -> SQLiteFileImporter.ImportError? {
        do {
            _ = try SQLiteFileImporter.validatedURL(forPath: path, fileManager: fileManager)
            return nil
        } catch let error as SQLiteFileImporter.ImportError {
            return error
        } catch {
            Issue.record("expected an ImportError, got \(error)")
            return nil
        }
    }

    // MARK: - The accepted shape

    @Test("A regular file inside managed storage is accepted and returned resolved")
    func fileInsideManagedStorageIsAccepted() throws {
        try withStorage { storage in
            let file = try writeFile(
                at: storage.managedDirectory.appendingPathComponent("db.sqlite"),
                fileManager: storage.fileManager
            )

            let validated = try SQLiteFileImporter.validatedURL(
                forPath: file.path,
                fileManager: storage.fileManager
            )

            #expect(validated == file.standardizedFileURL.resolvingSymlinksInPath(),
                    "the caller deletes this exact URL, so it must be the resolved one")
        }
    }

    /// Symlinks are resolved, not banned. The guard's rule is about *where the bytes are*, and a
    /// link that lands inside managed storage lands on a file the app already owns.
    @Test("A symlink that resolves to a file inside managed storage is accepted")
    func symlinkStayingInsideManagedStorageIsAccepted() throws {
        try withStorage { storage in
            let target = try writeFile(
                at: storage.managedDirectory.appendingPathComponent("real.sqlite"),
                fileManager: storage.fileManager
            )
            let link = storage.managedDirectory.appendingPathComponent("alias.sqlite")
            try storage.fileManager.createSymbolicLink(at: link, withDestinationURL: target)

            let validated = try SQLiteFileImporter.validatedURL(
                forPath: link.path,
                fileManager: storage.fileManager
            )

            #expect(validated == target.standardizedFileURL.resolvingSymlinksInPath())
        }
    }

    // MARK: - The refusals

    @Test("A path outside managed storage is refused")
    func pathOutsideManagedStorageIsRefused() throws {
        try withStorage { storage in
            let outside = try writeFile(
                at: storage.sandbox.appendingPathComponent("elsewhere.sqlite"),
                fileManager: storage.fileManager
            )

            #expect(refusal(forPath: outside.path, fileManager: storage.fileManager)
                    == .outsideManagedDirectory)
        }
    }

    /// The delete-outside-the-sandbox case, stated plainly.
    ///
    /// The link *is* inside managed storage; only its target is not. Without
    /// `resolvingSymlinksInPath` the component comparison would be made against the link's own
    /// path, accept it, and `removeItem` would follow the link and delete the target.
    @Test("A symlink inside managed storage pointing outside it is refused")
    func symlinkEscapingManagedStorageIsRefused() throws {
        try withStorage { storage in
            let outside = try writeFile(
                at: storage.sandbox.appendingPathComponent("precious.sqlite"),
                fileManager: storage.fileManager
            )
            let link = storage.managedDirectory.appendingPathComponent("innocent.sqlite")
            try storage.fileManager.createSymbolicLink(at: link, withDestinationURL: outside)

            #expect(refusal(forPath: link.path, fileManager: storage.fileManager)
                    == .outsideManagedDirectory)
            #expect(FileManager.default.fileExists(atPath: outside.path),
                    "the guard must not have been the thing that decided this file's fate")
        }
    }

    /// Why the implementation compares `pathComponents` instead of the path string.
    ///
    /// `…/SQLite Databases-evil/db.sqlite` string-prefixes `…/SQLite Databases`, so a `hasPrefix`
    /// check accepts it and the caller then deletes a file in a directory the app does not own.
    /// The test asserts both halves: that the guard refuses it, and that the naive check it
    /// replaced would not have.
    @Test("A sibling directory that only prefixes the managed directory's name is refused")
    func siblingDirectoryThatOnlyPrefixesTheNameIsRefused() throws {
        try withStorage { storage in
            let evilDirectory = URL(fileURLWithPath: storage.managedDirectory.path + "-evil", isDirectory: true)
            let file = try writeFile(
                at: evilDirectory.appendingPathComponent("db.sqlite"),
                fileManager: storage.fileManager
            )

            #expect(refusal(forPath: file.path, fileManager: storage.fileManager)
                    == .outsideManagedDirectory)

            let resolvedRoot = storage.managedDirectory.resolvingSymlinksInPath().path
            #expect(file.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot),
                    "if this stops being true the test has stopped exercising the prefix trap")
        }
    }

    @Test("Parent traversal out of managed storage is refused")
    func parentTraversalIsRefused() throws {
        try withStorage { storage in
            let outside = try writeFile(
                at: storage.sandbox.appendingPathComponent("escaped.sqlite"),
                fileManager: storage.fileManager
            )
            // …/Application Support/glassdb/SQLite Databases/../../../escaped.sqlite
            let traversal = storage.managedDirectory
                .appendingPathComponent("..")
                .appendingPathComponent("..")
                .appendingPathComponent("..")
                .appendingPathComponent(outside.lastPathComponent)

            #expect(refusal(forPath: traversal.path, fileManager: storage.fileManager)
                    == .outsideManagedDirectory)
        }
    }

    @Test("A directory inside managed storage is not a regular file")
    func directoryInsideManagedStorageIsRefused() throws {
        try withStorage { storage in
            let directory = storage.managedDirectory.appendingPathComponent("db.sqlite", isDirectory: true)
            try storage.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            #expect(refusal(forPath: directory.path, fileManager: storage.fileManager)
                    == .sourceIsNotAFile)
        }
    }

    /// The managed directory itself has exactly as many components as the root, which is why the
    /// guard requires strictly more. Accepting it would hand `removeItem` the whole store.
    @Test("The managed directory itself is refused")
    func managedDirectoryItselfIsRefused() throws {
        try withStorage { storage in
            #expect(refusal(forPath: storage.managedDirectory.path, fileManager: storage.fileManager)
                    == .outsideManagedDirectory)
        }
    }

    /// Distinct from `.outsideManagedDirectory` on purpose: this is the one refusal
    /// `removeUnreferencedSQLiteFile` swallows, because a file that is already gone needs no
    /// delete and no log line.
    @Test("A nonexistent path reports the copy missing, not an escape")
    func nonexistentPathReportsMissing() throws {
        try withStorage { storage in
            let absent = storage.managedDirectory.appendingPathComponent("never-written.sqlite")

            #expect(refusal(forPath: absent.path, fileManager: storage.fileManager)
                    == .managedCopyMissing)
        }
    }

    @Test("A nonexistent path outside managed storage also reports missing, and reveals nothing")
    func nonexistentPathOutsideAlsoReportsMissing() throws {
        try withStorage { storage in
            let absent = storage.sandbox.appendingPathComponent("never-written.sqlite")

            #expect(refusal(forPath: absent.path, fileManager: storage.fileManager)
                    == .managedCopyMissing,
                    "existence is checked first; the guard does not confirm what is outside it")
        }
    }

    @Test("An empty path is refused rather than resolved against the working directory")
    func emptyPathIsRefused() throws {
        try withStorage { storage in
            #expect(refusal(forPath: "", fileManager: storage.fileManager) != nil)
        }
    }

    // MARK: - The round trip

    /// `importFile` ends by passing its own output through `validatedURL`, so the two must agree.
    /// A snapshot that the guard then refuses would leave an orphaned file in managed storage that
    /// nothing can ever delete.
    @Test("An imported database validates against the guard that will later delete it")
    func importedFileValidates() throws {
        try withStorage { storage in
            let source = storage.sandbox.appendingPathComponent("source.sqlite")
            // A zero-length file is a valid, empty SQLite database.
            try writeFile(at: source, fileManager: storage.fileManager)
            try Data().write(to: source)

            let imported = try SQLiteFileImporter.importFile(
                at: source,
                fileManager: storage.fileManager
            )

            #expect(imported.pathExtension == "sqlite")
            let revalidated = try SQLiteFileImporter.validatedURL(
                forPath: imported.path,
                fileManager: storage.fileManager
            )
            #expect(revalidated == imported)
        }
    }

    @Test("A directory cannot be imported")
    func importingADirectoryIsRefused() throws {
        try withStorage { storage in
            let directory = storage.sandbox.appendingPathComponent("folder", isDirectory: true)
            try storage.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            #expect(throws: SQLiteFileImporter.ImportError.sourceIsNotAFile) {
                _ = try SQLiteFileImporter.importFile(at: directory, fileManager: storage.fileManager)
            }
        }
    }
}
